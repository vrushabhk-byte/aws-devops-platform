# Contributing

1. Create a feature branch.
2. Run `pip install -r requirements-dev.txt` and `pytest -v`.
3. Run `terraform -chdir=terraform fmt -recursive` and review the Terraform plan in your own AWS account.
4. Open a pull request against `main`.
5. Never commit credentials, Terraform state, plans, or `terraform.tfvars`.
