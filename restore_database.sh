#!/bin/bash

################################################################################
# Database Restore Script for SaaS Application
# 
# This script restores a PostgreSQL database from a backup file
# Usage: ./restore_database.sh <backup_file> [environment]
# Example: ./restore_database.sh backups/backup_development_20260108_120000.sql development
################################################################################

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
DB_USER="amars"
DB_HOST="localhost"
DB_PORT="5432"

# Check if backup file is provided
if [ -z "$1" ]; then
    echo -e "${RED}Error: Backup file not specified${NC}"
    echo ""
    echo "Usage: $0 <backup_file> [environment]"
    echo ""
    echo "Available backups:"
    ls -lh backups/backup_*.sql 2>/dev/null || echo "  No backups found"
    exit 1
fi

BACKUP_FILE="$1"

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo -e "${RED}Error: Backup file not found: ${BACKUP_FILE}${NC}"
    echo ""
    echo "Available backups:"
    ls -lh backups/backup_*.sql 2>/dev/null || echo "  No backups found"
    exit 1
fi

# Determine environment from backup filename or argument
ENVIRONMENT="${2:-development}"
if [[ "$BACKUP_FILE" =~ backup_([a-z]+)_ ]]; then
    DETECTED_ENV="${BASH_REMATCH[1]}"
    if [ -z "$2" ]; then
        ENVIRONMENT="$DETECTED_ENV"
    fi
fi

case $ENVIRONMENT in
  development)
    DB_NAME="saasapplication_development"
    ;;
  test)
    DB_NAME="saasapplication_starter_test"
    ;;
  production)
    DB_NAME="saasapplication_production"
    ;;
  *)
    echo -e "${RED}Error: Invalid environment '${ENVIRONMENT}'${NC}"
    echo "Usage: $0 <backup_file> [development|test|production]"
    exit 1
    ;;
esac

# Get backup file info
FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
FILE_DATE=$(stat -c %y "$BACKUP_FILE" 2>/dev/null || stat -f "%Sm" "$BACKUP_FILE")

# Print restore information
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Database Restore Script${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "Environment:  ${GREEN}${ENVIRONMENT}${NC}"
echo -e "Database:     ${GREEN}${DB_NAME}${NC}"
echo -e "Backup file:  ${GREEN}${BACKUP_FILE}${NC}"
echo -e "File size:    ${GREEN}${FILE_SIZE}${NC}"
echo -e "Created:      ${GREEN}${FILE_DATE}${NC}"
echo ""

# Warning for production
if [ "$ENVIRONMENT" = "production" ]; then
    echo -e "${RED}⚠️  WARNING: You are about to restore the PRODUCTION database!${NC}"
    echo -e "${RED}This will overwrite all current production data!${NC}"
    echo ""
    read -p "Are you ABSOLUTELY sure? Type 'YES' to continue: " CONFIRM
    if [ "$CONFIRM" != "YES" ]; then
        echo "Restore cancelled"
        exit 0
    fi
fi

# Confirmation
echo -e "${YELLOW}⚠️  This will replace ALL data in the '${DB_NAME}' database${NC}"
echo -e "${YELLOW}Current data will be permanently lost!${NC}"
echo ""
read -p "Do you want to continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

# Check PostgreSQL connection
echo ""
echo -e "${YELLOW}Checking PostgreSQL connection...${NC}"
if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to PostgreSQL server${NC}"
    echo "Please ensure PostgreSQL is running: sudo service postgresql start"
    exit 1
fi
echo -e "${GREEN}✓ PostgreSQL is running${NC}"

# Drop existing database (if exists) and recreate
echo ""
echo -e "${YELLOW}Preparing database...${NC}"
export PGPASSWORD="password"

# Terminate existing connections
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$DB_NAME' AND pid <> pg_backend_pid();" \
    > /dev/null 2>&1

# Drop and recreate database
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS $DB_NAME;" > /dev/null 2>&1
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;" > /dev/null 2>&1

echo -e "${GREEN}✓ Database prepared${NC}"

# Restore the backup
echo ""
echo -e "${YELLOW}Restoring backup...${NC}"
echo "This may take a few moments depending on backup size..."
echo ""

if psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" < "$BACKUP_FILE" > /dev/null 2>&1; then
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}✓ Restore completed successfully!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "Database:   ${GREEN}${DB_NAME}${NC}"
    echo -e "Restored:   ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
    
    # Get table count
    TABLE_COUNT=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ')
    
    if [ ! -z "$TABLE_COUNT" ]; then
        echo -e "${BLUE}Database statistics:${NC}"
        echo -e "  Tables restored: ${GREEN}${TABLE_COUNT}${NC}"
        echo ""
    fi
    
    echo -e "${BLUE}Next steps:${NC}"
    echo "  1. Verify data: rails console"
    echo "  2. Run pending migrations (if any): rails db:migrate"
    echo "  3. Restart your application"
    echo ""
    
else
    echo ""
    echo -e "${RED}================================${NC}"
    echo -e "${RED}✗ Restore failed!${NC}"
    echo -e "${RED}================================${NC}"
    echo "Please check the error messages above"
    exit 1
fi

# Unset password
unset PGPASSWORD

exit 0
