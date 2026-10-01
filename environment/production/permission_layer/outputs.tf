output "ec2_private_role" {
  value = aws_iam_instance_profile.ec2_profile.role

}
output "ec2_instance_profile" {
  value = aws_iam_instance_profile.ec2_profile.name
}
output "ec2_sg"{
    value = aws_security_group.private_sg.id
}
output "public_sg"{
    value = aws_security_group.sg_public_user.id
}
output "sg_alb"{
    value = aws_security_group.sg_alb.id
}
output "sg_rds"{
    value = aws_security_group.sg_rds.id
}