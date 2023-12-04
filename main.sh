#/bin/bash

# Variables
SATELLITE_SERVER="km-dmz-satellite.com"
ORG="TESTORG"
RHEL_7_ACTIVATION_KEY="RHEL_7"
RHEL_8_ACTIVATION_KEY="RHEL_8"
RHEL9_ACTIVATION_KEY="RHEL_9"
NEW_USER="testuser"
NEW_USER_PASS="testuser"

# Functions
# Function to check if command exists
function command_exists() {
    command -v "$@" >/dev/null 2>&1
}

# Main code
# Detect which version of RHEL is running and assign the correct activation key
if [ -f /etc/redhat-release ]; then
    RHEL_VERSION=$(cat /etc/redhat-release | awk '{print $7}' | cut -d. -f1)
    if [ "$RHEL_VERSION" == "7" ]; then
        ACTIVATION_KEY=$RHEL_7_ACTIVATION_KEY
    elif [ "$RHEL_VERSION" == "8" ]; then
        ACTIVATION_KEY=$RHEL_8_ACTIVATION_KEY
    elif [ "$RHEL_VERSION" == "9" ]; then
        ACTIVATION_KEY=$RHEL_9_ACTIVATION_KEY
    else
        echo "Unable to determine RHEL version. Aborting."
        exit 1
    fi
else
    echo "Unable to determine RHEL version. Aborting."
    exit 1
fi

# Create a new user with sudo privileges
if ! id -u "$NEW_USER" >/dev/null 2>&1; then
    useradd -m "$NEW_USER"
    echo "$NEW_USER:$NEW_USER_PASS" | chpasswd
    usermod -aG wheel "$NEW_USER"
fi

# check the satellite capsule for connectivity and cert errors
# if no errors, continue
# if errors, exit with error message

if curl -k https://$SATELLITE_SERVER/pub/katello-ca-consumer-latest.noarch.rpm -o /dev/null -w "%{http_code}\n" | grep -q 200; then
    echo "Connection to $SATELLITE_SERVER successful."
else
    echo "Unable to connect to $SATELLITE_SERVER. Aborting."
    exit 1
fi

# download and install katello-ca-consumer-latest.noarch.rpm using dnf
# include error handling incase a cert error is received or site is unreachable

if command_exists dnf; then
    dnf -y install http://$SATELLITE_SERVER/pub/katello-ca-consumer-latest.noarch.rpm
elif command_exists yum; then
    yum -y install http://$SATELLITE_SERVER/pub/katello-ca-consumer-latest.noarch.rpm
else
    echo "Neither yum nor dnf found. Aborting."
    exit 1
fi

# Register the system with the satellite server
subscription-manager register --org="$ORG" --activationkey="$ACTIVATION_KEY"


# Enable the correct repos for the version of RHEL includeng 7, 8, and 9
if [ "$RHEL_VERSION" == "7" ]; then
    subscription-manager repos --enable=rhel-7-server-rpms --enable=rhel-7-server-satellite-tools-6.8-rpms --enable=rhel-server-rhscl-7-rpms
elif [ "$RHEL_VERSION" == "8" ]; then
    subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms --enable=rhel-8-for-x86_64-appstream-rpms --enable=rhel-8-for-x86_64-highavailability-rpms --enable=rhel-8-for-x86_64-satellite-tools-6.8-rpms --enable=ansible-2.9-for-rhel-8-x86_64-rpms
elif [ "$RHEL_VERSION" == "9" ]; then
    subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms --enable=rhel-9-for-x86_64-appstream-rpms --enable=rhel-9-for-x86_64-highavailability-rpms --enable=rhel-9-for-x86_64-satellite-tools-6.8-rpms --enable=ansible-2.9-for-rhel-9-x86_64-rpms
else
    echo "Unable to determine RHEL version. Aborting."
    exit 1
fi

# We will not be using the katello agent, remove it if it exists
if command_exists katello-agent; then
    yum remove -y katello-agent
fi

