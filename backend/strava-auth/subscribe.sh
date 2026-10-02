#!/bin/zsh
# Manages the Strava webhook subscription for the Tileroam Worker (one per Strava application).
#
#   STRAVA_CLIENT_ID=… STRAVA_CLIENT_SECRET=… STRAVA_VERIFY_TOKEN=… WORKER_URL=https://….workers.dev \
#     backend/strava-auth/subscribe.sh create   # register <WORKER_URL>/webhook with Strava
#   … subscribe.sh view                         # show the current subscription (its id)
#   … subscribe.sh delete <id>                  # remove it
#
# Strava checks the callback right away: deploy the Worker with STRAVA_VERIFY_TOKEN set first.
set -euo pipefail
: ${STRAVA_CLIENT_ID:?} ${STRAVA_CLIENT_SECRET:?}
API=https://www.strava.com/api/v3/push_subscriptions
case ${1:-} in
  create)
    : ${STRAVA_VERIFY_TOKEN:?} ${WORKER_URL:?}
    curl -sS -X POST $API -F client_id=$STRAVA_CLIENT_ID -F client_secret=$STRAVA_CLIENT_SECRET \
      -F callback_url=${WORKER_URL%/}/webhook -F verify_token=$STRAVA_VERIFY_TOKEN; echo ;;
  view)
    curl -sS -G $API -d client_id=$STRAVA_CLIENT_ID -d client_secret=$STRAVA_CLIENT_SECRET; echo ;;
  delete)
    curl -sS -X DELETE "$API/${2:?subscription id}?client_id=$STRAVA_CLIENT_ID&client_secret=$STRAVA_CLIENT_SECRET"; echo ;;
  *) echo "usage: subscribe.sh create | view | delete <id>" >&2; exit 1 ;;
esac
