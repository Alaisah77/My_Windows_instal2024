
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
    description = "Allow ALB to connect the instance"
    from_port   = 8883
    to_port     = 8883
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }


  ingress {
    description = "Allow ALB to connect the instance"
    from_port   = 8880
    to_port     = 8880
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
  monitoring                  = true

  user_data = <<-EOF
              
            <powershell>
      
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force

            $DEST_DIR = "C:\\modelizeIT"

            if (-Not (Test-Path -Path $DEST_DIR)) {
                New-Item -Path $DEST_DIR -ItemType Directory
            }

            Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

            choco install 7zip -y

            $InstallerPath = "$env:TEMP\\AWSCLIV2.msi"
            Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $InstallerPath
            Start-Process msiexec.exe -ArgumentList "/i $InstallerPath /quiet" -Wait
            Remove-Item -Path $InstallerPath

            $TempFilePath = "$env:TEMP\\modelizeIT-AnalysisServer.zip"
            aws s3 cp "s3://saas-sandbox-staging/ModelizeIT/modelizeIT-AnalysisServer.zip" $TempFilePath

            & "C:\\Program Files\\7-Zip\\7z.exe" x $TempFilePath -o$DEST_DIR

            Remove-Item -Path $TempFilePath

            Set-Location -Path "$DEST_DIR\\bin"

            .\\RejuvenApptor-start.ps1
            .\\modelizeIT-start.ps1
            .\\Gatherer-JobRunner.ps1
            .\\Gatherer-UI.ps1

            Set-ItemProperty -Path 'HKLM:\\System\\CurrentControlSet\\Control\\Terminal Server' -Name 'fDenyTSConnections' -Value 0

            Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

            $password = ConvertTo-SecureString "YourSecurePassword" -AsPlainText -Force
            Set-LocalUser -Name "Administrator" -Password $password
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
    "arn:aws:sns:us-east-1:123456789012:my-sns-topic" # Add SNS topic for notification
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
