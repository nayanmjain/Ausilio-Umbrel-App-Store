export APP_CAL_DIY_ENCRYPTION_KEY="$(derive_entropy "${app_entropy_identifier}-calendso-key" | cut -c1-32)"
