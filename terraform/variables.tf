variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "terraform-ec2"
}

variable "ssh_key_name" {
  description = "(Optional) existing EC2 key pair name for SSH access"
  type        = string
  default     = ""
}
