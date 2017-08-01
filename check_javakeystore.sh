#!/bin/sh
#
# Jan-Otto Kröpke; 01.08.2017
#
########################################################
#
#       Check certificates inside a java keystore
#           based on https://www.davidgouveia.net/2013/07/simple-script-to-check-expiry-dates-on-a-java-keystore-jks-file/
#
########################################################
TIMEOUT="timeout 5s "
KEYTOOL="$TIMEOUT keytool"
KEYSTORE=""
PASSWORD=""
PERF=""
RET=0
MESSAGE=""
ARGS=`getopt -o "p:k:w:c:" -l "password:,keystore:,warning:,critical:" -n "$0" -- "$@"`

function usage {
  echo "Usage: $0 --keystore <keystore> [--password <password>] --warning <number of days until expiry> --critical <number of days until expiry>"
  exit
}

function start {
  CURRENT=`date +%s`

  WARNING_THRESHOLD=$(($CURRENT + ($WARNING_THRESHOLD_IN_DAYS*24*60*60)))
  CRITICAL_THRESHOLD=$(($CURRENT + ($CRITICAL_THRESHOLD_IN_DAYS*24*60*60)))
  if [ $WARNING_THRESHOLD -le $CURRENT ] || [ $CRITICAL_THRESHOLD -le $CURRENT ]; then
    echo "[ERROR] Invalid date."
    exit 1
  fi
  $KEYTOOL -list -v -keystore "$KEYSTORE"  $PASSWORD 2>&1 > /dev/null
  if [ $? -gt 0 ]; then echo "Error opening the keystore."; exit 1; fi

  while IFS=' ' read -r ALIAS
  do
    #Iterate through all the certificate alias
    EXPIRACY=`$KEYTOOL -list -v -keystore "$KEYSTORE"  $PASSWORD -alias $ALIAS | grep Valid`
    UNTIL=`$KEYTOOL -list -v -keystore "$KEYSTORE"  $PASSWORD -alias $ALIAS | grep Valid | perl -ne 'if(/until: (.*?)\n/) { print "$1\n"; }'`
    UNTIL_SECONDS=`date -d "$UNTIL" +%s`
    REMAINING_DAYS=$(( ($UNTIL_SECONDS -  $(date +%s)) / 60 / 60 / 24 ))

    if [ $UNTIL_SECONDS -le 0 ]; then
      MESSAGE="$MESSAGE\n[CRITICAL] Certificate '$ALIAS' has already expired since '$UNTIL'"
      RET=2
    elif [ $CRITICAL_THRESHOLD -ge $UNTIL_SECONDS ]; then
      MESSAGE="$MESSAGE\n[CRITICAL] Certificate '$ALIAS' expires in '$UNTIL' ($REMAINING_DAYS day(s) remaining)."
      RET=2
    elif [ $WARNING_THRESHOLD -ge $UNTIL_SECONDS ]; then
      MESSAGE="$MESSAGE\n[WARNING]  Certificate '$ALIAS' expires in '$UNTIL' ($REMAINING_DAYS day(s) remaining)."
      [ "$RET" -eq 0 ] && RET=1
    else
      MESSAGE="$MESSAGE\n[OK]       Certificate '$ALIAS' expires in '$UNTIL' ($REMAINING_DAYS day(s) remaining)."
    fi

    PERF="$PERF '$ALIAS'=$(( $UNTIL_SECONDS - $CURRENT ))s;$(( $WARNING_THRESHOLD_IN_DAYS*24*60*60 ));$(( $CRITICAL_THRESHOLD_IN_DAYS*24*60*60 ));;;"
  done <<< "$($KEYTOOL -list -v -keystore $KEYSTORE $PASSWORD | grep Alias | cut -d' ' -f3)"

  [ "$MESSAGE" != "" ] && MESSAGE="$MESSAGE\n"

  case "$RET" in
    0)
      echo "KEYSTORE OK: All certificates are not expired"
      echo -ne $MESSAGE
      ;;

    1)
      echo "KEYSTORE WARNING: Some certificates expire soon."
      echo -ne $MESSAGE
      ;;

    2)
      echo "KEYSTORE CRITICAL: Some certificates expire soon or are expired."
      echo -ne $MESSAGE
      ;;
  esac

  echo " |$PERF"

  exit $RET
}

eval set -- "$ARGS"

while true
do
  case "$1" in
    -p|--password)
      if [ -n "$2" ]; then PASSWORD=" -storepass $2"; else echo "Invalid password"; exit 1; fi
      shift 2;;
    -k|--keystore)
      if [ ! -f "$2" ]; then echo "Keystore not found: $1"; exit 1; else KEYSTORE=$2; fi
      shift 2;;
    -w|--warning)
      if [ -n "$2" ] && [[ $2 =~ ^[0-9]+$ ]]; then WARNING_THRESHOLD_IN_DAYS=$2; else echo "Invalid threshold"; exit 1; fi
      shift 2;;
    -c|--critical)
      if [ -n "$2" ] && [[ $2 =~ ^[0-9]+$ ]]; then CRITICAL_THRESHOLD_IN_DAYS=$2; else echo "Invalid threshold"; exit 1; fi
      shift 2;;
    --)
      shift
      break;;
  esac
done

if [ -z "$KEYSTORE" ] || [ -z "$WARNING_THRESHOLD_IN_DAYS" ] || [ -z "$CRITICAL_THRESHOLD_IN_DAYS" ]
then
  usage
else
  start
fi
