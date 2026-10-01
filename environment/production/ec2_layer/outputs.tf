# output "instance_ids" {
#   value = { for k, mod in module.ec2-private : k => mod.instance_id }
# }

# output "public_ip" {
#   value = module.bastion.public_ip
# }
# output "private_ip" {
#   value = module.ec2-private[*].private_ip
# }
# output "eip" {
#   value = aws_eip.bastion_eip.public_ip
# }

# output "private_ip" {
#   value = { for k, mod in module.ec2-private : k => mod.private_ip }
# }

# output "name" {
#   value = { for k, mod in module.ec2-private : k => mod.name }
# }
