# Intersight - Server Inventory
Before running this script, you will need API keys generated from your Intersight account. Download the secret key file to the same directory as the script (or change line 5 of the script to reflect the actual path to the secret key file) and paste the API key from Intersight in the marked spot on line 4. You will also need to install the Intersight PowerShell module if you haven't already (https://community.cisco.com/t5/data-center-and-cloud-blogs/getting-started-with-the-intersight-powershell-sdk/ba-p/4823398)

To run the script, open Powershell7 and navigate to the directory with the script and run .\server_inventory.ps1. The script will complete and generate a .csv file with the inventory for all servers in the Intersight instance
