# aberrant-scripts
Public scripts intended to perform simple tasks for the [Aberrant](https://www.aberrant.io/) RemoteAgent

## Scripts
See the README in each subfolder for a list of what scripts are available.

### How to use a script

1. Download a copy of the script into the RemoteAgent's `Scripts` folder
2. Edit the script to provide any parameters, or if indicated configure the Remote Agent machine to authenticate to a third party service
3. Copy the script's contract (from the script's `contract.json`) into the RemoteAgent's `contracts.config.json`
4. Utilize the RemoteAgent `TestMode` to verify your script is able to be executed.

#### Script Configuration
The Aberrant RemoteAgent maintains metadata for each script it is given access to in the `contracts.config.json` in the `Scripts` subfolder.

Each script in this repository contains a `contract.json` file with a snippit of json that needs to be added to the `contracts.config.json` in order for a script to be available to the Remote Agent.

## Contributing or Modifying Scripts
See the README in each scripting engine subfolder for script requirements.