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

  source_ranges = ["192.168.0.0/16"]

  allow {
    protocol = "all"
  }
}
