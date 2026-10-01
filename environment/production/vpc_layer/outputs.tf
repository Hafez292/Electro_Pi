output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" { 
  value = module.vpc.pri_sub_id
}

output "public_subnet_ids" { 
    value= module.vpc.pub_sub_id
}

