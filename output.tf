output "ssh-command" {
  value = "ssh -i ${aws_key_pair.ec2_key.key_name}.pem ec2-user@${aws_instance.DockerInstance.public_dns}"
}

output "public-ip" {
  value = aws_instance.DockerInstance.public_ip
}
output "link" {
  value = aws_lb.my_load_balancer.dns_name
}
output "dns-link" {
  value = aws_route53_record.www.fqdn
}