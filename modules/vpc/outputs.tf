output "vpc_id" {
    value = aws_vpc.main.id  
}

output "pub_sub_id" {
  value = [for s in aws_subnet.public : s.id]
}

output "pri_sub_id" {
  value = [for s in aws_subnet.private : s.id]
}

