resource "google_project_service" "vpcaccess" {
  project            = var.project_id
  service            = "vpcaccess.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "bookflow_vpc" {
  name                    = "bookflow-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"

  depends_on = [
    google_project_service.required["compute.googleapis.com"],
  ]
}

resource "google_compute_subnetwork" "bookflow_main" {
  name          = "bookflow-main-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.bookflow_vpc.id
  ip_cidr_range = "192.168.10.0/24"
}

resource "google_vpc_access_connector" "bookflow" {
  name          = "bookflow-vpc-conn"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.bookflow_vpc.name
  ip_cidr_range = "192.168.254.0/28"

  depends_on = [
    google_project_service.vpcaccess,
  ]
}

resource "google_compute_firewall" "bookflow_internal" {
  name        = "bookflow-allow-internal"
  project     = var.project_id
  network     = google_compute_network.bookflow_vpc.name
  description = "Allow internal BOOKFLOW traffic inside the GCP foundation VPC."
  direction   = "INGRESS"
  priority    = 1000

  source_ranges = [
    "192.168.0.0/16", # GCP internal
    "10.0.0.0/16",    # AWS BookFlow AI VPC
    "10.1.0.0/16",    # AWS Sales Data VPC
    "10.2.0.0/16",    # AWS Egress VPC
    "10.3.0.0/16",    # AWS Data VPC
    "10.4.0.0/16",    # AWS Ansible VPC
  ]

  allow {
    protocol = "all"
  }
}

# 1. 구글 서비스가 사용할 내부 IP 대역 예약
resource "google_compute_global_address" "private_ip_alloc" {
  name          = "google-managed-services-bookflow-vpc"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.bookflow_vpc.id
  project       = var.project_id
}

# 2. 비공개 서비스 연결(VPC 피어링) 생성
resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.bookflow_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_alloc.name]

  # 서비스 네트워킹 API 활성화 후 진행되도록 설정
  depends_on = [
    google_project_service.required["servicenetworking.googleapis.com"]
  ]
}
