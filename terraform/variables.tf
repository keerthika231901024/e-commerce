variable "region" {
  default = "ap-southeast-1"
}

variable "profile" {
  default = "idp-sbx-trn-lab-01"
}

variable "project_name" {
  default = "keerthi"
}

variable "product_lambda_name" {
  default = "keerthika_product_service"
}

variable "cart_lambda_name" {
  default = "keerthika_cart_service"
}

variable "monitoring_email" {
  default = ""
}

variable "enable_monitoring" {
  default = false
}

variable "auth_allowed_origins" {
  type = list(string)
  default = [
    "http://localhost:5500",
    "http://127.0.0.1:5500",
    "https://dgebflsa5lqkq.cloudfront.net"
  ]
}