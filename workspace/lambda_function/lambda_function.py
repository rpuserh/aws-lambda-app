# lambda_function.py

import boto3
import json
import os
from datetime import datetime, timedelta, timezone

def handler(event, context):
    """
    This function describes all EC2 snapshots, identifies those older than
    a specified number of days, and deletes them.
    A 'dry_run' environment variable can be set to 'true' to prevent deletions.
    """
    # --- Configuration ---
    # Set to 'true' to only log what would be deleted.
    # It is STRONGLY recommended to run in 'dry_run' mode first.
    # This value is controlled by the Lambda environment variable set in Terraform.
    DRY_RUN = os.environ.get('dry_run', 'true').lower() == 'true'
    RETENTION_DAYS = 365

    # Initialize the EC2 client
    ec2 = boto3.client('ec2')
    
    # Calculate the cutoff date for deletion
    now = datetime.now(timezone.utc)
    cutoff_date = now - timedelta(days=RETENTION_DAYS)
    
    print(f"--- Snapshot Cleaner Started ---")
    print(f"Dry Run Mode: {DRY_RUN}")
    print(f"Retention period: {RETENTION_DAYS} days")
    print(f"Snapshots older than {cutoff_date.isoformat()} will be targeted for deletion.")

    snapshots_to_delete = []
    deleted_count = 0
    error_count = 0
    
    try:
        # Use a paginator to handle accounts with many snapshots
        paginator = ec2.get_paginator('describe_snapshots')
        pages = paginator.paginate(OwnerIds=['self'])
        
        for page in pages:
            for snapshot in page.get('Snapshots', []):
                if snapshot['StartTime'] < cutoff_date:
                    snapshots_to_delete.append(snapshot['SnapshotId'])

        if not snapshots_to_delete:
            print("No snapshots found older than the retention period.")
            return {'statusCode': 200, 'body': json.dumps('No old snapshots to delete.')}

        print(f"Found {len(snapshots_to_delete)} snapshots to be deleted: {snapshots_to_delete}")

        if DRY_RUN:
            summary = "Dry run complete. No snapshots were deleted. Check logs to see which snapshots would have been removed."
        else:
            print("--- Deletion Commencing ---")
            for snapshot_id in snapshots_to_delete:
                try:
                    print(f"Deleting snapshot: {snapshot_id}...")
                    ec2.delete_snapshot(SnapshotId=snapshot_id)
                    print(f"Successfully deleted snapshot: {snapshot_id}")
                    deleted_count += 1
                except Exception as e:
                    # Catch errors for individual deletions (e.g., snapshot is in use by an AMI)
                    print(f"Could not delete snapshot {snapshot_id}. Reason: {str(e)}")
                    error_count += 1
            
            summary = (
                f"Deletion complete. "
                f"Successfully deleted: {deleted_count}. "
                f"Failed to delete: {error_count}."
            )
        
        print(summary)
        return {'statusCode': 200, 'body': json.dumps({'summary': summary})}
        
    except Exception as e:
        print(f"An unhandled error occurred: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps(f"Error processing snapshots: {str(e)}")}