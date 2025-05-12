#!/usr/bin/env bash
# Unified Mail Admin Utility
# Combines Postfix, Dovecot, MySQL Virtual Mail management, plus safety checks and log parsing
# Usage: ./mail_admin_util.sh

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi

# Global Variables
MYSQL_DB="mailserver"
LOG_MAIL="/var/log/mail.log"
LOG_AUTH="/var/log/auth.log"

##########################
# Utility Functions      
##########################
confirm() {
  # $1: prompt
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy] ]] && return 0 || return 1
}

sanitize_input() {
  # remove dangerous characters
  echo "$1" | sed 's/[^a-zA-Z0-9@._-]//g'
}

##########################
# Log Parsing Functions  
##########################
parse_dovecot_logs() {
  echo -e "\nDovecot Authentication Log Parsing"
  read -rp "Filter by user (leave blank for all): " user
  FILTER=$(sanitize_input "$user")
  echo "Showing login events from $LOG_MAIL and $LOG_AUTH..."
  grep -E "dovecot.*(Login|Info)" "$LOG_MAIL" "$LOG_AUTH" \
    | grep -i "$FILTER" \
    | awk '{print $1, $2, $3, $0}'
}

parse_postfix_logs() {
  echo -e "\nPostfix Connection Log Parsing"
  read -rp "Filter by IP (leave blank for all): " ip
  FILTER=$(sanitize_input "$ip")
  grep "postfix/smtpd" "$LOG_MAIL" \
    | grep "$FILTER" \
    | awk '{print $1, $2, $3, $7, $8, $10}'
}

##########################
# MySQL Virtual Menu     
##########################
virtual_mail_menu() {
  read -sp "Enter MySQL root password: " MYSQL_PWD; echo
  MYSQL_CMD="mysql -u root -p$MYSQL_PWD -D $MYSQL_DB"

  while true; do
    echo -e "\n--- Virtual Mail MySQL Admin ---"
    echo "1) Add domain"
    echo "2) List domains"
    echo "3) Delete domain"
    echo "4) Add user"
    echo "5) List users"
    echo "6) Delete user"
    echo "7) Add alias"
    echo "8) List aliases"
    echo "9) Delete alias"
    echo "10) Add catch-all"
    echo "11) Delete catch-all"
    echo "12) Back"
    read -rp "Select an option [1-12]: " vchoice
    case "$vchoice" in
      1)
        read -rp "Domain name to add: " VD
        VD=$(sanitize_input "$VD")
        $MYSQL_CMD -e "INSERT INTO virtual_domains (name) VALUES ('$VD');"
        echo "Domain '$VD' added." ;;
      2)
        $MYSQL_CMD -e "SELECT id, name FROM virtual_domains;" ;;
      3)
        read -rp "Domain name to delete: " VD
        VD=$(sanitize_input "$VD")
        if confirm "Are you sure you want to delete domain $VD?"; then
          $MYSQL_CMD -e "DELETE FROM virtual_domains WHERE name='$VD';"
          echo "Domain '$VD' deleted."
        else
          echo "Deletion aborted."
        fi ;;
      4)
        read -rp "Mailbox to add (user@domain): " MU
        MU=$(sanitize_input "$MU")
        read -sp "Password for $MU: " MP; echo
        HASH=$(doveadm pw -s SHA256-CRYPT -p "$MP")
        IFS='@' read USER DOMAIN <<< "$MU"
        $MYSQL_CMD -e "INSERT INTO virtual_users (domain_id, local_part, password) \
          VALUES ((SELECT id FROM virtual_domains WHERE name='$DOMAIN'), '$USER', '$HASH');"
        echo "User '$MU' created." ;;
      5)
        $MYSQL_CMD -e "SELECT vu.id, vd.name, vu.local_part FROM virtual_users vu \
          JOIN virtual_domains vd ON vu.domain_id = vd.id;" ;;
      6)
        read -rp "User local part to delete (user@domain): " MU
        MU=$(sanitize_input "$MU")
        IFS='@' read USER DOMAIN <<< "$MU"
        if confirm "Delete user $MU?"; then
          $MYSQL_CMD -e "DELETE vu FROM virtual_users vu \
            JOIN virtual_domains vd ON vu.domain_id=vd.id \
            WHERE vd.name='$DOMAIN' AND vu.local_part='$USER';"
          echo "User '$MU' deleted."
        else
          echo "Aborted."
        fi ;;
      7)
        read -rp "Alias from (alias@domain): " AF
        AF=$(sanitize_input "$AF")
        read -rp "Alias to (destination): " AT
        AT=$(sanitize_input "$AT")
        IFS='@' read _ ADOMAIN <<< "$AF"
        $MYSQL_CMD -e "INSERT INTO virtual_aliases (domain_id, source, destination) \
          VALUES ((SELECT id FROM virtual_domains WHERE name='$ADOMAIN'), '$AF', '$AT');"
        echo "Alias '$AF' -> '$AT' added." ;;
      8)
        $MYSQL_CMD -e "SELECT id, source, destination FROM virtual_aliases;" ;;
      9)
        read -rp "Alias ID to delete: " AID
        if confirm "Delete alias ID $AID?"; then
          $MYSQL_CMD -e "DELETE FROM virtual_aliases WHERE id='$AID';"
          echo "Alias '$AID' deleted."
        else
          echo "Aborted."
        fi ;;
      10)
        read -rp "Catch-all domain (domain.com): " CAD
        CAD=$(sanitize_input "$CAD")
        read -rp "Forward to (user@domain): " CUT
        CUT=$(sanitize_input "$CUT")
        $MYSQL_CMD -e "INSERT INTO virtual_aliases (domain_id, source, destination) \
          VALUES ((SELECT id FROM virtual_domains WHERE name='$CAD'), '@$CAD', '$CUT');"
        echo "Catch-all '@$CAD' -> '$CUT' added." ;;
      11)
        read -rp "Catch-all domain to delete (domain.com): " CAD
        CAD=$(sanitize_input "$CAD")
        if confirm "Delete catch-all for $CAD?"; then
          $MYSQL_CMD -e "DELETE FROM virtual_aliases WHERE source='@$CAD';"
          echo "Catch-all for '$CAD' deleted."
        else
          echo "Aborted."
        fi ;;
      12)
        break ;;
      *) echo "Invalid selection." ;;
    esac
    echo -e "\nUpdating Postfix maps and reloading service..."
    postmap mysql_virtual_domains.cf
    postmap mysql_virtual_users.cf
    postmap mysql_virtual_aliases.cf
    systemctl reload postfix
  done
}

##########################
# Main Menu & Loop       
##########################
MAIN_TASKS=(
  "Postfix: Show mail queue"
  "Postfix: Flush mail queue"
  "Postfix: Delete message (with confirmation)"
  "Postfix: Purge deferred messages"
  "Postfix: Purge entire queue"
  "Postfix: Show active configuration"
  "Postfix: List map types"
  "Postfix: Reload service"
  "Dovecot: Mailbox status"
  "Dovecot: Rebuild mailbox index"
  "Dovecot: Force resync mailbox"
  "Dovecot: List users/mailboxes"
  "Dovecot: Show statistics"
  "Dovecot: Show active connections"
  "Dovecot: Show user quota"
  "Parse Dovecot logs (login events)"
  "Parse Postfix logs (connections)"
  "MySQL Virtual Mail Management"
  "Exit"
)

show_menu() {
  echo -e "\n=== Unified Mail Admin Utility ==="
  for i in "${!MAIN_TASKS[@]}"; do
    printf "%2d) %s\n" "$((i+1))" "${MAIN_TASKS[$i]}"
  done
}

while true; do
  show_menu
  read -rp "Select an option [1-${#MAIN_TASKS[@]}]: " choice
  case "$choice" in
    1) postqueue -p ;;                
    2) postqueue -f ;;                
    3)
      read -rp "Queue ID to delete: " QID
      if [[ -z "$QID" ]]; then echo "No ID provided."; continue; fi
      if postqueue -p | grep -q "$QID"; then
        if confirm "Delete message $QID?"; then
          postsuper -d "$QID" && echo "Deleted $QID.";
        else echo "Aborted."; fi
      else
        echo "Queue ID $QID not found.";
      fi ;;
    4) postsuper -d ALL deferred && echo "Deferred purged." ;;   
    5)
      if confirm "Purge entire queue?"; then
        postsuper -d ALL && echo "All messages purged.";
      else echo "Aborted."; fi ;;
    6) postconf -n ;;                
    7) postconf -m ;;                
    8) systemctl reload postfix && echo "Postfix reloaded." ;;    
    9) read -rp "User (user@domain): " MB; doveadm mailbox status -u "$MB" all ;;  
   10) read -rp "User (user@domain): " MB; doveadm index -u "$MB" rebuild ;;  
   11) read -rp "User (user@domain): " MB; doveadm force-resync -u "$MB" ;;  
   12) doveadm user '*' ;;         
   13) doveadm stats ;;            
   14) doveadm who ;;              
   15) read -rp "User (user@domain): " MB; doveadm quota get -u "$MB" ;;  
   16) parse_dovecot_logs ;;      
   17) parse_postfix_logs ;;      
   18) virtual_mail_menu ;;        
   19) echo "Exiting."; exit 0 ;;  
    *) echo "Invalid choice." ;;  
  esac
  read -rp "Press Enter to return to the menu..." ;
done
