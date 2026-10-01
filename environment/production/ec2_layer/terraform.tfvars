instance_name = "7ader-production"
#instance_type = "c3.xlarge" or "c6g.xlarge"
instance_type = "t3.medium"
key_name = "7ader"
add_tag = {
  "env" = "production-7ader"
}
root_volume_size = 20
volume_type = "gp3"