data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] 
}


resource "aws_instance" "ec2" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  key_name               = var.key_name
  vpc_security_group_ids = [var.security_group_id]
  associate_public_ip_address = var.enable_ip  
  iam_instance_profile = var.iam_instance_profile
  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.volume_type
  }
  tags = merge({Name = var.instance_name},var.add_tag)
}
