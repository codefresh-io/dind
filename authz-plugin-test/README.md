# Codefresh dockerd authorization plugin

### How to configure

By default the plugin reads the configuration file named pluginConfig.json from the same folder it is launched in, though it can be changed using the `--proxy-socket` parameter.

The `allowedPaths` object contains a mapping of the docker commands to regular expressions that should match against the client requests to filter out the allowed docker engine API paths.

The `allowedCreateOptions` object of the configuration JSON tends to reflect the same JSON structure as the body of the corresponding client requests.

Everytime the `create` API call is made, the plugin compares the client request JSON body with the configuration JSON and interprets the config values depending on data types of the request values, using the following rules:

##### boolean
- _false_ - the request value must be false
- _true_ - the request value must be true
- _"any"_ - the request value might be both true or false
##### string
- _""_ - only the default docker value is allowed for the request
- _"[some_regex]"_ - the request value must match the regular expression

##### integer
- _0_ - the request value must be the docker default value or literally zero
- [any number] - the request value should not be higher than the number

##### object or array
- {} - the request value might be any object
- [] - the request value might any array
- null - the request value must be null

### How to debug in Visual Studio Code

Assuming your OS is Linux, the instructions are:

1. Run vscode with root privileges (it is needed because the plugin binds to a unix socket)
2. Add the following launch configuration: 

```{
	"version": "0.2.0",
	"configurations": [
		{
			"name": "Launch",
			"type": "go",
			"request": "launch",
			"mode": "debug",
			"remotePath": "",
			"program": "${workspaceRoot}/plugin.go",
			"env": {},
			"args": [],
			"showLog": true
		}
	]
}
```
3. Launch the debugger
4. Stop the docker daemon:
```
sudo service docker stop
```
5. Start the docker daemon with the flag:
```
sudo dockerd --authorization-plugin=cf-authz-plugin
```
6. Go ahead and run a few docker commands