module "Bastion" {
  source            = "../../../modules/ec2"
  vpc_id            = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_id         = element(data.terraform_remote_state.vpc.outputs.public_subnet_ids, 0)
  security_group_id = data.terraform_remote_state.permission.outputs.public_sg
  instance_type     = var.instance_type
  enable_ip         = true
  key_name          = var.key_name
  instance_name     = "Bastion_Host"
  root_volume_size = var.root_volume_size
  volume_type = var.volume_type
}


module "private_ec2" {
  source            = "../../../modules/ec2"
  vpc_id            = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_id         = element(data.terraform_remote_state.vpc.outputs.private_subnet_ids, 0)
  security_group_id = data.terraform_remote_state.permission.outputs.ec2_sg
  instance_type     = var.instance_type
  enable_ip         = true
  key_name          = var.key_name
  instance_name     = "Application_Tier"
  iam_instance_profile = data.terraform_remote_state.permission.outputs.ec2_instance_profile
  root_volume_size = var.root_volume_size
  volume_type = var.volume_type
}

module "public_ec2" {
  source            = "../../../modules/ec2"
  vpc_id            = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_id         = element(data.terraform_remote_state.vpc.outputs.public_subnet_ids, 0)
  security_group_id = data.terraform_remote_state.permission.outputs.public_sg
  instance_type     = var.instance_type
  enable_ip         = true
  key_name          = var.key_name
  instance_name     = "Web_Tier"
  root_volume_size = var.root_volume_size
  volume_type = var.volume_type
}