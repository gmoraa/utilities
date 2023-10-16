#!/bin/bash -eu

# Set your Security group ID and EC2 instance ID
sg_group=""
ec2_instance=""

# Validate input arguments
if [[ $# -ne 1 ]]
then
	echo "Possible arguments are: 'ip' to whitelist your IP or 'key' to upload your ssh key."
	exit 1
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
    counter=-1
    existing_user=false
    rules=$(
        aws ec2 describe-security-group-rules \
        --filters Name="group-id",Values="$sg_group" \
        --query "SecurityGroupRules[*].{Name:Description,ID:SecurityGroupRuleId}" \
    )
    rule_names=($(echo $rules | jq -r '.[].Name'))
    rule_ids=($(echo $rules | jq -r '.[].ID'))

    for g in "${rule_names[@]}"
    do
        counter=$(( counter + 1 ))
        if [ "$user" == "$g" ]
        then
            existing_user=true
            break
        fi
    done

    if [ $existing_user == true ]
    then
        aws ec2 modify-security-group-rules \
             --group-id $sg_group \
             --security-group-rules SecurityGroupRuleId="${rule_ids[$counter]}",SecurityGroupRule="{Description="$user",IpProtocol=TCP,FromPort=22,ToPort=22,CidrIpv4=$cidr}" \
             >> /dev/null
        echo "Security group updated with IP '$ip' for user '$user'."
        exit 0
    else
        aws ec2 authorize-security-group-ingress \
            --group-id $sg_group \
            --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges="[{CidrIp=$cidr,Description='$user'}]" \
            >> /dev/null
        echo "Security group created with IP '$ip' for user '$user'."
        exit 0
    fi
}

# Uploads your public key to the bastion host.
key () {
    # Pending implementation.
    #
    # Upload user public key to S3
    # Triggers Lambda
    # Systems Manager(Run Command)
    # Add key(s) from S3 bucket to ~/.ssh/authorized_keys
    exit 0
}

input=$1
case $input
in
    ip) ip $@
            ;;
    key) key $@
            ;;
    *) echo "Invalid input"
       exit ;;
esac
