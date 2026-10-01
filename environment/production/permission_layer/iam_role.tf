#Private_EC2_IAM_Role & Instance Profile for EC2 instances in private subnets
resource "aws_iam_role" "ec2_private_role" {
name = "ec2-private-App-Tier" 

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

} # Attach Policies to the Role
resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ec2_private_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_attach_read_only" {
  role       = aws_iam_role.ec2_private_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
  
}
resource "aws_iam_role_policy_attachment" "rds_attach_full_access" {
  role       = aws_iam_role.ec2_private_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
  
}
resource "aws_iam_instance_profile" "ec2_profile" {  # To Attach the IAM Role to EC2 Instances
  name = "ec2-private-profile-production" 
  role = aws_iam_role.ec2_private_role.name
}


