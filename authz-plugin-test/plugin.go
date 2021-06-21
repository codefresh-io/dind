package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"os/user"
	"reflect"
	"regexp"
	"strconv"
	"strings"

	"github.com/docker/go-plugins-helpers/authorization"
)

type plugin struct {
	name string
}

var debugFlag = flag.Bool("debug", false, "Enable/disable the debug logs")
var configPath = flag.String("config", "./pluginConfig.json", "Specify the path for the config file")

var configAPIPaths map[string]interface{}
var configCreateOpts map[string]interface{}

func (p plugin) AuthZReq(req authorization.Request) authorization.Response {

	authRes := authorization.Response{
		Allow: false, // deny all requests by default
	}

	if val, _ := req.RequestHeaders["User"]; val != "freestyle" {
		authRes.Allow = true
		return authRes
	}

	if checkPath(&req.RequestURI, &authRes) {
		if checkOptions(&req.RequestURI, &req.RequestBody, &authRes) {
			authRes.Allow = true
		}
	}
	return authRes
}

func (p plugin) AuthZRes(req authorization.Request) authorization.Response {
	return authorization.Response{
		Allow: true}
}

func checkPath(uri *string, authRes *authorization.Response) bool { // check if the current request match any of the allowed

	for _, v := range configAPIPaths {
		r, _ := regexp.MatchString(v.(string), *uri)
		if r {
			return r
		}
	}

	authRes.Msg = "The request is not allowed"
	return false
}

func checkOptions(uri *string, body *[]byte, authRes *authorization.Response) bool {

	if strings.Contains(*uri, "/create") {
		var userCreateOpts map[string]interface{}
		if err := json.Unmarshal(*body, &userCreateOpts); err != nil {
			fmt.Println("error:", err)
		}

		if r, deniedOptString := goThroughAndCompare(userCreateOpts, configCreateOpts); !r {
			authRes.Msg = fmt.Sprintf(deniedOptString)
			return false
		}
	}

	return true
}

func goThroughAndCompare(a map[string]interface{}, b map[string]interface{}) (bool, string) {
	for k, v := range a {

		if len(b) == 0 { // if the option is an empty object in the config file, means any values are allowed
			continue
		}

		if match, _ := regexp.MatchString("\\/tcp", k); match { // handle the exceptional case, where there is a port number as a key name instead of being a key value
			k = "*/tcp"
		}

		if _, ok := b[k]; !ok {
			return false, fmt.Sprintf("The parameter %s is not defined in the security configuration, denying...", k)
		}

		switch v := v.(type) {
		case nil:
			if v == b[k] { // in case if the client request option is nil and the same is for the config - skip
				continue
			}
		case bool:
			switch t := b[k].(type) { // the field in the config might not only be a boolean
			case bool: // in case if the value in config is boolean, compare booleans
				if v != b[k] {
					return false, fmt.Sprintf("The flag %s is not allowed to be %v", k, v)
				}
			case string: // in case if the value in config is string, check if it equals "any"
				if t != "any" {
					return false, fmt.Sprintf("Invalid config value %s", b[k])
				}
			}
		case string:
			r, _ := regexp.MatchString(b[k].(string), v)
			if !r || b[k].(string) != v && b[k].(string) == "" {
				return false, fmt.Sprintf("%s is not allowed to be %v", k, v)
			}
		case float64:
			if v > b[k].(float64) && b[k].(float64) != -1 {
				return false, fmt.Sprintf("%s is not allowed to be higher than %v", k, b[k])
			}
		case []interface{}:
			if len(v) == 0 {
				continue // array is empty in the request, means nothing to check, continuing to the next option
			}
			switch bv := b[k].(type) {
			case []interface{}:
				if len(bv) == 0 { // array is empty in the config, means any values are allowed
					continue
				}
			FirstLoop:
				for _, v2 := range v { // go through the user request array values
					//go through the config array values and compare them with the user req value; break to the first loop on the first match
					for _, vb2 := range bv {
						switch vb2 := vb2.(type) {
						case string:
							r, _ := regexp.MatchString(vb2, v2.(string))
							if r {
								break FirstLoop
							}
						case float64:
							if v2.(float64) > vb2 && vb2 != -1 {
								return false, fmt.Sprintf("%s is not allowed to be higher than %v", k, vb2)
							}
							break FirstLoop
						case map[string]interface{}:
							if r, deniedOptString := goThroughAndCompare(v2.(map[string]interface{}), vb2); !r {
								return r, deniedOptString
							}
							break FirstLoop
						default:
							fmt.Printf("%v: %v, %v\n", k, v2, reflect.TypeOf(v2))

						}
					}
					return false, fmt.Sprintf("%s - %v is not allowed", k, v2)
				}
			default:
				return false, fmt.Sprintf("%s - %v is not allowed", k, v)
			}
		case map[string]interface{}:
			if len(v) == 0 { // map is empty in the request, means nothing to check, skipping
				continue
			}
			switch b := b[k].(type) {
			case map[string]interface{}:
				if r, deniedOptString := goThroughAndCompare(v, b); !r {
					return r, deniedOptString
				}
			default:
				return false, fmt.Sprintf("%s are not allowed", k)
			}
		default:
			return false, fmt.Sprintf("%s is not allowed", k)
		}
	}

	return true, ""
}

func readConfig(filePath string) {
	fmt.Printf("Reading the config file %s...\n", filePath)
	file, err := ioutil.ReadFile(filePath)

	if err != nil {
		fmt.Printf("error while reading the config file %s\n%s", filePath, err)
		os.Exit(1)
	}
	var conf map[string]interface{}
	if err = json.Unmarshal(file, &conf); err != nil {
		panic(err)
	} else {
		fmt.Printf("The config file has been read successfully\n")
	}

	configAPIPaths = conf["allowedPaths"].(map[string]interface{})
	configCreateOpts = conf["allowedCreateOptions"].(map[string]interface{})
}

func main() {

	flag.Parse()
	readConfig(*configPath)

	p := plugin{name: "cf-authz-plugin"}
	h := authorization.NewHandler(p)
	u, _ := user.Current()
	gid, _ := strconv.Atoi(u.Gid)

	go h.ServeUnix(p.name, gid) // TO DO: Add logging about successful/unsuccessful start of listening on the unix socket
	startProxy(gid)
}
