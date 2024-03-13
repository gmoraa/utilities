import json
import os
import paramiko
import boto3
from io import StringIO
import logging

def lambda_handler(event, context):
    try:
        ssh_key = event['sshKey']
        
        # Read the secret name and EC2 DNS from environment variables
        secret_name = os.environ.get('SECRET_NAME')
        ec2_dns = os.environ.get('EC2_DNS')
        
        if not secret_name or not ec2_dns:
            logging.error('Environment variables SECRET_NAME or EC2_DNS are not set.')
            return {
                'statusCode': 500,
                'body': json.dumps('Configuration error: missing SECRET_NAME or EC2_DNS')
            }
        
        # Fetch the EC2 instance SSH key from AWS Secrets Manager
        secrets_manager = boto3.client('secretsmanager')
        secret = secrets_manager.get_secret_value(SecretId=secret_name)
        ec2_ssh_key = secret['SecretString']  # Assuming the secret string directly contains the SSH key
        
        # Connect to the EC2 instance and add the public key to authorized_keys
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        # Loading the private key from a string
        pkey = paramiko.RSAKey(file_obj=StringIO(ec2_ssh_key))
        
        ssh.connect(ec2_dns, username='ec2-user', pkey=pkey)
        
        command = f'echo "{ssh_key}" >> ~/.ssh/authorized_keys'
        stdin, stdout, stderr = ssh.exec_command(command)
        
        ssh.close()
        
        return {
            'statusCode': 200,
            'body': json.dumps('Public SSH key added to EC2 instance')
        }
    except Exception as e:
        logging.error(f"An error occurred: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'An error occurred: {str(e)}')
        }
