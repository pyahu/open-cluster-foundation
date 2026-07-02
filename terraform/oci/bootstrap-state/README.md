# OCI Bootstrap State

Creates the OCI Object Storage bucket used by Terraform remote state. This
stack uses local state only once, before the main cluster state exists.

## 1. OCI Credentials

Create an API key for the user that will operate Terraform:

```sh
mkdir -p ~/.oci
openssl genrsa -out ~/.oci/pyahu-terraform.pem 2048
chmod 600 ~/.oci/pyahu-terraform.pem
openssl rsa -pubout \
  -in ~/.oci/pyahu-terraform.pem \
  -out ~/.oci/pyahu-terraform_public.pem
openssl rsa -pubout -outform DER \
  -in ~/.oci/pyahu-terraform.pem |
  openssl md5 -c
```

In the OCI console, upload `~/.oci/pyahu-terraform_public.pem` under:

`Identity & Security > Domains > Default domain > Users > <user> > API keys`

Then create or update `~/.oci/config`:

```ini
[PYAHU_TERRAFORM]
user=ocid1.user.oc1..aaaa...
fingerprint=aa:bb:cc:dd:...
tenancy=ocid1.tenancy.oc1..aaaa...
region=sa-saopaulo-1
key_file=/home/<user>/.oci/pyahu-terraform.pem
```

Validate the profile:

```sh
oci os ns get --profile PYAHU_TERRAFORM
```

## 2. Compartment, Group and Policies

These steps need a tenancy administrator identity (they are done once per
tenancy, not per cluster).

Create a dedicated compartment for the cluster:

```sh
oci iam compartment create \
  --compartment-id <tenancy_ocid> \
  --name ocf-clusters \
  --description "Open Cluster Foundation clusters"
```

Create the Terraform administrators group and add your user to it. In the OCI
console: `Identity & Security > Domains > Default domain > Groups > Create
group` (name it `ocf-cluster-admins`), then add the user that owns the API key
from step 1. Tenancies created since 2023 use Identity Domains, so the console
path is the reliable one; older tenancies can also use
`oci iam group create` / `oci iam group add-user`.

To create only the state bucket, the group needs Object Storage access in the
compartment:

```sh
oci iam policy create \
  --compartment-id <tenancy_ocid> \
  --name ocf-cluster-admins-state \
  --description "Terraform remote state for Open Cluster Foundation" \
  --statements '[
    "Allow group ocf-cluster-admins to manage object-family in compartment ocf-clusters",
    "Allow group ocf-cluster-admins to read compartments in tenancy"
  ]'
```

For the `foundation` module, add the policies listed in
[its README](../foundation/README.md#2-iam-policies).

## 3. Create the State Bucket

```sh
cd terraform/oci/bootstrap-state
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your compartment OCID and region.

```sh
terraform init
terraform plan
terraform apply
```

The `backend_hcl` output is already formatted for the main module:

```sh
terraform output -raw backend_hcl
```

Copy that content to:

```text
terraform/oci/foundation/backend.hcl
```

## 4. Security Notes

- `terraform.tfvars`, `backend.hcl` and local state files are ignored by Git.
- The bucket is created with `NoPublicAccess` and versioning enabled.
- The `oci` backend uses the local OCI credential profile; no S3 compatibility
  Customer Secret Key is required.
- Keep the private key outside the repository.
