#!/bin/bash -eu

# Validate input arguments
if [[ $# -ne 1 ]]
then
	echo "Possible arguments are: 'ip' to whitelist your IP or 'key' to upload your ssh key."
	exit 10
fi

if ! aws sts get-caller-identity >> /dev/null
then
    echo "Configure your AWS credentials with: 'aws configure' or set yur profile with 'export AWS_PROFILE=<something>'."
    exit 1
fi

# Create or update the security rules to allow one IP per developer
ip () {
    ip=$(curl -s -4 icanhazip.com)
    cidr="$ip/32"
    user=$(whoami)
    counter=0
    existing_user=false

    # Get the exiting rule and parse them
    rules=$(aws ec2 describe-security-group-rules \
            --filters 'Name="group-id",Values="sg-xxxxxxxxxxxxxxxxx"' \
            --query "SecurityGroupRules[*].{Name:Description,ID:SecurityGroupRuleId}")

    IFS=$'\n' rule_names=($(echo "$rules" | jq -r '.[].Name'))
    IFS=$'\n' rule_ids=($(echo "$rules" | jq -r '.[].ID'))

    # Loop each rule
    for g in "${rule_names[@]}"
    do
        if [[ "$user" == "$g" ]]
        then
            existing_user=true
            break
        fi
        counter=$(( counter + 1 ))
    done

    if [[ "$existing_user" == true ]]
    then 
        # Update inbound rule
        aws ec2 modify-security-group-rules \
             --group-id sg-xxxxxxxxxxxxxxxxx \
             --security-group-rules "SecurityGroupRuleId=${rule_ids[$counter]},SecurityGroupRule={Description=$user,IpProtocol=tcp,FromPort=22,ToPort=22,CidrIpv4=$cidr}" \
             > /dev/null
        echo "Inbound rule updated with IP '$ip' for user '$user'."
    else 
        # Create inbound rule
        aws ec2 authorize-security-group-ingress \
            --group-id sg-xxxxxxxxxxxxxxxxx \
            --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=$cidr,Description=$user}]" \
            > /dev/null
        echo "Inbound rule created with IP '$ip' for user '$user'."
    fi
}

key () {
    public_keys=($(ls ~/.ssh/*.pub))
    PS3='Please select the SSH public key to upload: '
    select key in "${public_keys[@]}"
    do
        if [[ -n $key ]]; then
            echo "Selected key is: $key"
            pubkey_content=$(cat "$key")
            formatted_pubkey_content=$(printf "%s\\n" "$pubkey_content")
            aws lambda invoke \
                --function-name SSHKeyToBastion \
                --invocation-type RequestResponse \
                --payload '{"sshKey":"'"$formatted_pubkey_content"'"}' \
                --cli-binary-format raw-in-base64-out \
                response.json
            
            if [[ $? -eq 0 ]]; then
                # Optionally, inspect response.json or output to determine success
                echo "Lambda function invoked successfully. Checking response..."
                
                # Extract statusCode and body message from response.json
                statusCode=$(jq -r '.statusCode' response.json)
                responseBody=$(jq -r '.body' response.json)

                # Check if statusCode is 200 for success
                if [[ $statusCode -eq 200 ]]; then
                    echo "SSH public key upload successful."
                    echo "Message: $responseBody"
                else
                    echo "SSH public key upload failed."
                    echo "Error: $responseBody"
                    return 1
                fi
            else
                echo "Failed to invoke Lambda function."
                return 1
            fi
            break
        else
            echo "No key selected."
            return 1
        fi
    done
    return 0
}

input=$1
case $input
in
    ip) ip "$@"
            ;;
    key) key "$@"
            ;;
    *) echo "Invalid input"
       exit ;;
esac
