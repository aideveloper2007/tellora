#!/bin/bash

################################################################################
# Database Backup Script for SaaS Application
# 
# This script creates a complete backup of your PostgreSQL database
# Usage: ./backup_database.sh [development|test|production]
# Default: development
################################################################################

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration from database.yml
DB_USER="amars"
DB_HOST="localhost"
DB_PORT="5432"

# Determine which environment to backup
ENVIRONMENT="${1:-development}"

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
    echo "Usage: $0 [development|test|production]"
    exit 1
    ;;
esac

# Create backup directory if it doesn't exist
BACKUP_DIR="$(pwd)/backups"
mkdir -p "$BACKUP_DIR"

# Generate timestamp for backup file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${BACKUP_DIR}/backup_${ENVIRONMENT}_${TIMESTAMP}.sql"

# Print backup information
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Database Backup Script${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "Environment:  ${GREEN}${ENVIRONMENT}${NC}"
echo -e "Database:     ${GREEN}${DB_NAME}${NC}"
echo -e "User:         ${GREEN}${DB_USER}${NC}"
echo -e "Host:         ${GREEN}${DB_HOST}:${DB_PORT}${NC}"
echo -e "Backup file:  ${GREEN}${BACKUP_FILE}${NC}"
echo ""

# Check if PostgreSQL is running
echo -e "${YELLOW}Checking PostgreSQL connection...${NC}"
if ! pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to PostgreSQL server${NC}"
    echo "Please ensure PostgreSQL is running: sudo service postgresql start"
    exit 1
fi
echo -e "${GREEN}✓ PostgreSQL is running${NC}"
echo ""

# Check if database exists
echo -e "${YELLOW}Checking if database exists...${NC}"
if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
    echo -e "${RED}Error: Database '${DB_NAME}' does not exist${NC}"
    echo "Available databases:"
    psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -l
    exit 1
fi
echo -e "${GREEN}✓ Database exists${NC}"
echo ""

# Create the backup
echo -e "${YELLOW}Creating backup...${NC}"
echo "This may take a few moments depending on database size..."
echo ""

# Note: You'll be prompted for password (default: password)
export PGPASSWORD="password"
if pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -F p -f "$BACKUP_FILE"; then
    # Get file size
    FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}✓ Backup completed successfully!${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "File:     ${GREEN}${BACKUP_FILE}${NC}"
    echo -e "Size:     ${GREEN}${FILE_SIZE}${NC}"
    echo -e "Created:  ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
    
    # List recent backups
    echo -e "${BLUE}Recent backups in ${BACKUP_DIR}:${NC}"
    ls -lh "$BACKUP_DIR"/backup_*.sql 2>/dev/null | tail -5 | while read -r line; do
        echo "  $line"
    done
    echo ""
    
    # Cleanup old backups (keep last 10)
    BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/backup_${ENVIRONMENT}_*.sql 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 10 ]; then
        echo -e "${YELLOW}Note: You have ${BACKUP_COUNT} backups for ${ENVIRONMENT} environment${NC}"
        echo "Consider cleaning up old backups to save space"
        echo ""
    fi
    
    echo -e "${BLUE}To restore this backup later, run:${NC}"
    echo "  psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME < $BACKUP_FILE"
    echo ""
    
else
    echo ""
    echo -e "${RED}================================${NC}"
    echo -e "${RED}✗ Backup failed!${NC}"
    echo -e "${RED}================================${NC}"
    echo "Please check the error messages above"
    exit 1
fi

# Unset password
unset PGPASSWORD

exit 0
