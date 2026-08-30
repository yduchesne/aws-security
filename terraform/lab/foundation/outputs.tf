output "dev_lab_vpc_id" {
  description = "ID of the dedicated Dev Lab exercise VPC."
  value       = aws_vpc.dev_lab.id
}

output "dev_lab_public_subnet_id" {
  description = "ID of the tagged public subnet used by Exercise 8."
  value       = aws_subnet.dev_lab_public.id
}

output "dev_lab_public_subnet_availability_zone" {
  description = "Availability Zone selected for the Dev Lab public exercise subnet."
  value       = aws_subnet.dev_lab_public.availability_zone
}

output "dev_lab_public_route_table_id" {
  description = "ID of the public route table associated with the exercise subnet."
  value       = aws_route_table.dev_lab_public.id
}
