variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the existing VPC"
  type        = string
}

variable "subnet_id" {
  description = "The ID of the existing subnet"
  type        = string
}

variable "instance_type" {
  description = "The type of EC2 instance"
  default     = "t2.micro"
}

variable "s3_bucket_name" {
  description = "The name of the S3 bucket containing the application"
  type        = string
}

variable "application_port" {
  description = "The port where the application is exposed"
  default     = 8883
}

variable "endpoint" {
  description = "This is for the endpoint for the SNS topic"
  default     = ""
}