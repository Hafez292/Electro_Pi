resource "aws_security_group" "private_sg" {
  name        = "private_sg"
  description = "Security group for EC2 instances running Docker Compose"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  
 ingress {
    description = "traffic from anywhere"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ec2_sg"
  
  }
}

## SG-For Public_User
resource "aws_security_group" "sg_public_user" {
  name        = "sg_public_use"
  description = "Security group for Public Users Access"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  
  ingress {
    description = "traffic from my ip"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
   ingress {
    description = "All traffic from production_and_staging_vpc"
    from_port   = 0
    to_port     = 0 
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
     Name        = "sg-public_user"
  
  }
 
}

#SG_For_RDS
resource "aws_security_group" "sg_rds" {
  name        = "sg_rds"
  description = "Security group for RDS"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id  
  ingress {
    description = "traffic from private_sg"
    from_port   = 1433
    to_port     = 1433
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name        = "sg_rds"
  }
  
  }

