import os
import sys
import email
from email.policy import default

def find_maildirs(root_dir):
    """
    Recursively finds all directories containing 'cur' and 'new' Maildir folders.
    """
    maildirs = []
    for dirpath, dirnames, filenames in os.walk(root_dir):
        if 'cur' in dirnames or 'new' in dirnames:
            maildirs.append(dirpath)
    return maildirs

def process_maildir(maildir):
    """
    Removes duplicate emails (based on Message-ID) in 'cur' and 'new' folders within the given maildir.
    """
    msgids = set()
    removed_count = 0
    for subfolder in ['cur', 'new']:
        folder_path = os.path.join(maildir, subfolder)
        if not os.path.isdir(folder_path):
            continue
        for filename in os.listdir(folder_path):
            filepath = os.path.join(folder_path, filename)
            if not os.path.isfile(filepath):
                continue
            try:
                with open(filepath, 'rb') as f:
                    msg = email.message_from_binary_file(f, policy=default)
                msgid = msg.get('Message-ID')
                if not msgid:
                    # No Message-ID; skip or optionally handle as special case
                    continue
                if msgid in msgids:
                    print(f"Duplicate found: {filepath} (Message-ID: {msgid.strip()}) -- Removing.")
                    os.remove(filepath)
                    removed_count += 1
                else:
                    msgids.add(msgid)
            except Exception as e:
                print(f"Error processing {filepath}: {e}")
    return removed_count

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 remove_duplicate_maildir.py <mail_root_directory>")
        sys.exit(1)

    root_maildir = sys.argv[1]
    print(f"Scanning for Maildir folders in: {root_maildir}")

    maildirs = find_maildirs(root_maildir)
    print(f"Found {len(maildirs)} Maildir folders.")

    total_removed = 0
    for maildir in maildirs:
        removed = process_maildir(maildir)
        if removed > 0:
            print(f"Removed {removed} duplicate emails from {maildir}")
        total_removed += removed

    print(f"Done. Total duplicate emails removed: {total_removed}")
