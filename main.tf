
# Generate an SSH key pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "key_pair" {
  key_name   = "modelizeit-key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}

# Security Group
resource "aws_security_group" "instance_sg" {
  name        = "modelizeit_sg"
  description = "Allow RDP, HTTPS traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow RDP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Fetch the latest Windows Server AMI
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["801119661308"] 

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Elastic IP
resource "aws_eip" "instance_eip" {
  instance = aws_instance.windows_instance.id
}

# EC2 Instance
resource "aws_instance" "windows_instance" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  key_name                    = aws_key_pair.key_pair.key_name
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  associate_public_ip_address = true
  monitoring = true

  user_data = <<-EOF
              <powershell>
              # Install IIS
              Install-WindowsFeature -name Web-Server

              # Download and Install ModelizeIT Gatherer
              Import-Module BitsTransfer
              Start-BitsTransfer -Source "https://${var.s3_bucket_name}/ModelizeIT/ModelizeIT-Gatherer.zip" -Destination "C:\\inetpub\\wwwroot\\ModelizeIT-Gatherer.zip"
              Expand-Archive -Path "C:\\inetpub\\wwwroot\\ModelizeIT-Gatherer.zip" -DestinationPath "C:\\inetpub\\wwwroot\\ModelizeIT-Gatherer"

              # Restart IIS
              Restart-WebAppPool -Name "DefaultAppPool"
              </powershell>
              EOF

  tags = {
    Name = "ModelizeIT_Gatherer"
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu_alarm" {
  alarm_name          = "HighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 600
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "This alarm triggers if CPU utilization exceeds 80% for 5 minutes"
  dimensions = {
    InstanceId = aws_instance.windows_instance.id
  }
  actions_enabled = true

  alarm_actions = [
    "arn:aws:sns:us-east-1:123456789012:my-sns-topic"  # Add SNS topic for notification
  ]
}

resource "aws_sns_topic" "alarm_topic" {
  name = "windows_gatherer"
}

resource "aws_sns_topic_subscription" "my_email" {
  topic_arn = aws_sns_topic.alarm_topic.arn
  protocol  = "email"
  endpoint  = "var.endpoint"
}
