# ~/bin/redhat-aws.sh  (SOURCE THIS FILE)
# shellcheck disable=SC2034

# --- settings ---
CSV="${CSV:-$HOME/Documents/btofel_accessKeys.csv}"
PROFILE="${PROFILE:-redhat}"
REGION="${REGION:-us-east-1}"
OUTPUT="${OUTPUT:-json}"
# -----------------

# must be sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "ERROR: this script must be sourced, not run directly."
  echo "Usage: source $0"
  exit 1
fi

echo "==> clearing AWS_* env vars in this shell"
# broad unset (works for bash/zsh)
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN \
      AWS_REGION AWS_DEFAULT_REGION AWS_PROFILE AWS_DEFAULT_PROFILE 2>/dev/null || true
# zsh pattern unset (safe no-op in bash)
unset -m 'AWS_*' 2>/dev/null || true

echo "==> reading keys from: $CSV"
if [ ! -f "$CSV" ]; then
  echo "ERROR: CSV not found: $CSV" >&2
  return 1
fi

# CSV like: "Access key ID,Secret access key" on line 1; keys on line 2
read -r AK SK < <(awk -F, 'NR==2{gsub(/\r/,"",$1); gsub(/\r/,"",$2); print $1, $2}' "$CSV")
if [ -z "${AK:-}" ] || [ -z "${SK:-}" ]; then
  echo "ERROR: could not parse access key & secret from CSV (check header and second line)" >&2
  return 1
fi

echo "==> writing profile: $PROFILE"
aws configure set aws_access_key_id     "$AK" --profile "$PROFILE"
aws configure set aws_secret_access_key "$SK" --profile "$PROFILE"
aws configure set region                "$REGION" --profile "$PROFILE"
aws configure set output                "$OUTPUT" --profile "$PROFILE"

echo "==> also writing DEFAULT profile"
aws configure set aws_access_key_id     "$AK" --profile default
aws configure set aws_secret_access_key "$SK" --profile default
aws configure set region                "$REGION" --profile default
aws configure set output                "$OUTPUT" --profile default

# make this shell use the redhat profile by default
export AWS_PROFILE="$PROFILE"
unset AWS_REGION AWS_DEFAULT_REGION  # let config decide

# helper that always ignores any stray AWS_* for the call
aws_clean () {
  env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
      -u AWS_REGION -u AWS_DEFAULT_REGION -u AWS_PROFILE -u AWS_DEFAULT_PROFILE \
      aws "$@"
}

echo "==> verification (should show Type=config, not env)"
aws configure list

echo "==> identity (should be the redhat/default creds)"
aws sts get-caller-identity

echo "Ready. This shell is now on profile: $AWS_PROFILE"
echo "Tip: use 'aws_clean ...' to force-ignore any stray env for a single command."
