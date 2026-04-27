import functions_framework


@functions_framework.http
def handler(request):
    return "BookFlow AI GCP Function - Deployment Test Success"
