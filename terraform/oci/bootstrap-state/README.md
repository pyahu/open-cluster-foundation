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

## 2. Minimal IAM Policies

Use a dedicated compartment for the cluster. To create only the state bucket,
the Terraform administrators group needs Object Storage access in that
compartment:

```text
Allow group pyahu-cluster-admins to manage object-family in compartment <compartment-name>
Allow group pyahu-cluster-admins to read compartments in tenancy
```

For the `foundation` module, add the policies listed in its README.

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
