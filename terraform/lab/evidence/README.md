# Lab S3 data-event evidence

This independent Terraform root creates a customer-managed, S3-only AWS
CloudTrail organization trail for lab bucket data events. It does not modify or
adopt the Control Tower-managed organization trail.

The root is deployed after the Control Tower landing zone and Identity Center
are healthy:

```text
bootstrap → identity-center → lab-evidence → Week 2 exercises
```

It uses `ct-bootstrap` in the management account to create the organization
trail and assumes the existing `AWSControlTowerExecution` role in the Log
Archive account to create the dedicated evidence bucket. This is an initial
bootstrap operation, not a steady-state human access pattern.

The trail records S3 object data events only for bucket ARNs beginning with
`lab_bucket_name_prefix`. It excludes management events so it does not duplicate
the Control Tower trail. AWS requires global-service event inclusion to be
enabled on a multi-Region trail, but the data-only advanced selector prevents
those management events from being recorded. Logs are delivered to:

```text
s3://aws-security-lab-evidence-<MANAGEMENT_ACCOUNT_ID>/AWSLogs/<ORGANIZATION_ID>/<MEMBER_ACCOUNT_ID>/
```

`WorkloadLabAdministrator` has read-only identity permissions for the Dev Lab
and Test Lab prefixes. The bucket policy independently restricts access to the
Identity Center-provisioned role pattern in each lab account. Lab users cannot
write, delete, or administer evidence.

The root intentionally supports complete destruction. It does not use
`prevent_destroy`, and the bucket uses `force_destroy = true`, so a reviewed
`terraform apply -destroy` or `terraform destroy` removes the trail, bucket,
versions, and retained evidence. Preserve required evidence before destruction.

Operate it through:

```bash
./tf.sh --phase lab-evidence --dry-run
./tf.sh --phase lab-evidence --apply
```

Destroy only after reviewing the destroy plan:

```bash
terraform -chdir=terraform/lab/evidence plan -destroy
terraform -chdir=terraform/lab/evidence apply -destroy
```
