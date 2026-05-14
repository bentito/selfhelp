# ~/bin/redhat-aws.sh  (SOURCE THIS FILE)
# shellcheck disable=SC2034

# --- settings ---
# Account: NIDS Team AWS Dev (<your-aws-account-id>)
PROFILE="${PROFILE:-nids-dev}"
REGION="${REGION:-us-east-1}"
KERBEROS_ID="btofel"
SAML_ACCOUNT_ID="<your-aws-account-id>"
SAML_ROLE_NAME="admin"
VENV_PATH="/Users/btofel/workspace/selfhelp/.aws-saml-venv"
# -----------------

# must be sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "ERROR: this script must be sourced, not run directly."
  echo "Usage: source $0"
  exit 1
fi

echo "==> clearing AWS_* env vars in this shell"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
      AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_DEFAULT_PROFILE 2>/dev/null || true
unset -m 'AWS_*' 2>/dev/null || true

# 1) Check Kerberos ticket
echo "==> verifying Kerberos ticket..."
if ! klist -s; then
    echo "==> No active Kerberos ticket found. Please authenticate:"
    kinit "${KERBEROS_ID}@IPA.REDHAT.COM" || return 1
fi

# 2) Check if AWS token is valid
export AWS_PROFILE="$PROFILE"
echo "==> checking AWS session for profile: $AWS_PROFILE"
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo "==> session expired or not found. refreshing via aws-saml.py..."
    
    if [[ ! -d "$VENV_PATH" ]]; then
        echo "ERROR: SAML virtualenv not found at $VENV_PATH" >&2
        return 1
    fi

    # Run the SAML tool from the venv
    # Note: aws-saml.py will prompt for role selection if multiple are found, 
    # but we pre-specify account/role to minimize friction.
    (
        source "$VENV_PATH/bin/activate"
        aws-saml.py --target-account "$SAML_ACCOUNT_ID" \
                    --target-role "$SAML_ROLE_NAME" \
                    --profile "$AWS_PROFILE"
    )
fi

# helper that always ignores any stray AWS_* for the call
aws_clean () {
  env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
      -u AWS_REGION -u AWS_DEFAULT_REGION -u AWS_PROFILE -u AWS_DEFAULT_PROFILE \
      aws "$@"
}

echo "==> verification"
aws configure list --profile "$AWS_PROFILE"

echo "==> identity"
aws sts get-caller-identity --profile "$AWS_PROFILE"

echo "Ready. This shell is now on profile: $AWS_PROFILE"
