



>[! NOTE] 
> A comprehensive Bash utility that wraps common Postfix (postconf, postsuper, postqueue) and Dovecot (doveadm) commands into an interactive menu. This script
> provides a way to easily extend or customize with additional tasks or tweak options as needed. 

>[! TIP] 
> This script has, among other things: [!] A MySQL-driven submenu for virtual domain, user, alias, and catch-all management—prompting for the root 
> password, executing inserts into the typical virtual_domains, virtual_users, and virtual_aliases tables, then rebuilding Postfix maps and reloading the 
> service. Let me know if your schema or map filenames differ, and I can adjust those queries or filenames accordingly.

[! IMPORTANT]
> Originally, I had split out the MySQL virtual‐mail management into its own standalone script (mysql_virtual_mail.sh), added listing and exit options, and 
> had envisioned the Postfix/Dovecot menu in mail_admin_util.sh. Both assume the mailserver schema and typical mysql_virtual_*.cf map files—just drop them 
> into your bin/ and make executable (chmod +x). Pay attention to if your table names or map filenames differ, 

> ## I added delete options after this rendition 
> * consolidated everything into one script (mail_admin_util.sh) with a top-level menu for Postfix and Dovecot tasks, plus a nested MySQL section offering 
> add/list/delete for domains, users, aliases, and catch-alls. After each change it rebuilds the Postfix maps and reloads the service. 


## Additional knowledge helpful for this utility:
#
#!/usr/bin/env bash
# Author:  Aaron Surina aaron@surina.shop
#
# Unified Mail Admin Utility
#
# Combines Postfix, Dovecot, MySQL Virtual Mail management, plus safety checks and log parsing
#
# Usage: ./mail_admin_util.sh

# Ensure script is run as root
```if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root." >&2
  exit 1
fi
```
# Global Variables
```MYSQL_DB="mailserver"
LOG_MAIL="/var/log/mail.log"
LOG_AUTH="/var/log/auth.log"
```
##########################
# Utility Functions      
##########################
```confirm() {
  # $1: prompt
  read -rp "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy] ]] && return 0 || return 1
}

sanitize_input() {
  # remove dangerous characters
  echo "$1" | sed 's/[^a-zA-Z0-9@._-]//g'
}
```
##########################
# Log Parsing Functions  
##########################
```parse_dovecot_logs() {
  echo -e "\nDovecot Authentication Log Parsing"
  read -rp "Filter by user (leave blank for all): " user
```



** Safety checks: confirmation prompts before any delete/purge action and input sanitization. **

** Log parsing: menu options to grep Dovecot auth events and Postfix connections (with basic filters). **

** Error handling: validating queue IDs before deletion.**
