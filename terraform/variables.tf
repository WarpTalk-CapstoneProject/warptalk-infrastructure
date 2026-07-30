variable "aws_region" {
  description = "The AWS region to deploy to"
  default     = "ap-southeast-1" # Singapore
}

variable "instance_type" {
  description = "The EC2 instance type"
  default     = "t3.2xlarge"
}

variable "key_name" {
  description = "The name of the SSH Key Pair to use"
  default     = "warptalk-key"
}

variable "root_volume_size" {
  description = "Size of the root EBS volume in GB"
  default     = 100
}
