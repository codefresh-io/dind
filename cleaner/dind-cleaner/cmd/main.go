/*
Copyright 2018 The Codefresh Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package main

import (
	"bufio"
	"flag"
	"os"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/client"
	"github.com/golang/glog"
	"golang.org/x/net/context"
)

func readFileLines(path string) ([]string, error) {
	var lines []string
	if path == "" {
		return lines, nil
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	return lines, scanner.Err()
}

var dryRun *bool

const (
	cmdImages = "images"

	statusFound               = "found"
	statusRemoved             = "removed"
	statusRetainedByList      = "retainedByList"
	statusRetainedByDate      = "retainedByDate"
	statusChildRetained       = "childRetained"
	statusChildFailedToRemove = "childFailedToRemove"
	statusFailedToRemove      = "failedToRemove"
)

func _stringInList(list []string, s string) bool {
	for _, a := range list {
		if a == s {
			return true
		}
	}
	return false
}

func cleanImages(retainedImagesList []string, retainPeriod int64) {
	glog.Infof("Entering cleanImages, length of retainedImagesList = %d", len(retainedImagesList))
	if os.Getenv("DOCKER_API_VERSION") == "" {
		os.Setenv("DOCKER_API_VERSION", "1.35")
	}

	cli, err := client.NewEnvClient()
	if err != nil {
		panic(err)
	}

	type imageToCleanStruct = struct {
		ID          string
		Created     int64
		ParentID    string
		status      string
		tags        []string
		childrenIDs map[string]string
		size        int64
	}

	/*
		Purpose: remove images starting from first child excluding ids in retainedImagesList
		Logic:
		1. get All images (with All=true)
		2. fill map of imageToCleanStruct - for each image fill its children in the map of [id]"status"
		3. find images with no children
		4. loop by found images with no children and delete them, then update childrenList of whole map of imageToCleanStruct.
		   Skip deletion for images in retainedImagesList
		--- Repeat 3-4 until images to delete found

	*/

	// 1. Get All Images
	ctx := context.Background()
	imagesFullList, err := cli.ImageList(ctx, types.ImageListOptions{All: true})
	if err != nil {
		panic(err)
	}

	glog.Infof("Found %d images in docker", len(imagesFullList))

	currentTs := time.Now().Unix()
	// 2. fill map of imageToCleanStruct
	images := make(map[string]*imageToCleanStruct)
	for _, img := range imagesFullList {
		images[img.ID] = &imageToCleanStruct{
			ID:          img.ID,
			Created:     img.Created,
			ParentID:    img.ParentID,
			status:      statusFound,
			tags:        img.RepoTags,
			size:        img.Size,
			childrenIDs: make(map[string]string),
		}
	}

	glog.Infof("Calculating child images ...")
	for imageID, img := range images {
		if img.ParentID != "" {
			parentImage, parentImageInList := images[img.ParentID]
			if parentImageInList {
				parentImage.childrenIDs[imageID] = statusFound
			}
		}
	}

	// Loop until found some imagesToDelete
	var imagesToDelete []string
	loopCount := 0
	for {
		imagesToDelete = nil
		loopCount++
		// 3. finding all images with no children
		glog.Infof("\n\n#################\n------ Loop %d - finding images without any children to remove ...", loopCount)
		for imageID, img := range images {
			if len(img.childrenIDs) == 0 && (img.status == statusFound || img.status == statusChildFailedToRemove) {
				imagesToDelete = append(imagesToDelete, imageID)
			}
		}

		if len(imagesToDelete) == 0 {
			glog.Infof("Stopping - no images leave to remove ...")
			break
		}

		// 4. Loop by found images and delete|retain , then update whole images map
		glog.Infof("Found %d images with no children", len(imagesToDelete))
		for _, imageID := range imagesToDelete {
			glog.Infof("\n     Check if to remove image %s - %v", imageID, images[imageID].tags)
			// checking if image in retained list

			if _stringInList(retainedImagesList, imageID) {
				glog.Infof("   Skiping image %s - %v , it appears in retained list", imageID, images[imageID].tags)
				images[imageID].status = statusRetainedByList
			} else if retainPeriod > 0 && images[imageID].Created > 0 && images[imageID].Created < currentTs &&
				currentTs-images[imageID].Created < retainPeriod {

				glog.Infof("   Skiping image %s - %v , its created more than retainPeriod %d seconds ago", imageID, images[imageID].tags, retainPeriod)
				images[imageID].status = statusRetainedByDate
			} else {
				glog.Infof("   Deleting image %s - %v", imageID, images[imageID].tags)
				// add image delete here
				var err error
				if !*dryRun {
					_, err = cli.ImageRemove(ctx, imageID, types.ImageRemoveOptions{Force: true, PruneChildren: false})
				} else {
					glog.Infof("DRY RUN - do not actually delete")
				}

				if err == nil {
					glog.Infof("   image %s - %v has been deleted", imageID, images[imageID].tags)
					images[imageID].status = statusRemoved
				} else {
					glog.Infof("   FAILED to delete image %s - %v - %v", imageID, images[imageID].tags, err)
					images[imageID].status = statusFailedToRemove
				}
			}

			glog.Infof("   setting image status to %s", images[imageID].status)
			for _, img := range images {
				if _, ok := img.childrenIDs[imageID]; ok {
					if images[imageID].status == statusRemoved {
						glog.Infof("       deleting the child from parent image %s - %v", img.ID, img.tags)
						delete(img.childrenIDs, imageID)
					} else if images[imageID].status == statusRetainedByList || images[imageID].status == statusRetainedByDate {
						glog.Infof("       setting child status %s for image %s - %v", images[imageID].status, img.ID, img.tags)
						img.childrenIDs[imageID] = images[imageID].status
						img.status = statusChildRetained

					} else if images[imageID].status == statusFailedToRemove {
						glog.Infof("       setting child status %s and deleting the from parent image %s - %v", images[imageID].status, img.ID, img.tags)
						delete(img.childrenIDs, imageID)
						img.status = statusChildFailedToRemove
					}
				}
			}
		}
	}

	glog.Info("\n################\nPrinting results ..")
	var totalImagesSize, removedSize, retainedByListSize, retainedByDateSize, failedToRemoveSize int64
	for _, img := range images {
		glog.Infof("%s: %v - %s, size = %d", img.status, img.tags, img.ID, img.size)
		for childID, childStatus := range img.childrenIDs {
			glog.Infof("      Child: %s - %s (grandchild retained)", childID, childStatus)
		}

		totalImagesSize += img.size
		switch img.status {
		case statusRemoved:
			removedSize += img.size
		case statusRetainedByList:
			retainedByListSize += img.size
		case statusRetainedByDate:
			retainedByDateSize += img.size
		case statusFailedToRemove:
			failedToRemoveSize += img.size
		}
	}

	glog.Infof("\n-----------\n"+
		"    total images shared size: %.3f Mb \n"+
		"         removed shared size: %.3f  Mb \n"+
		"retained shared by list size: %.3f  Mb \n"+
		"retained shared by date size: %.3f  Mb \n"+
		"       failed to remove size: %.3f  Mb ",
		float64(totalImagesSize)/1024/1024.0,
		float64(removedSize)/1024/1024.0,
		float64(retainedByListSize)/1024/1024.0,
		float64(retainedByDateSize)/1024/1024.0,
		float64(failedToRemoveSize)/1024/1024.0)
}

func main() {

	usage := `
Usage: dind-cleaner <command> [options]

Commands:
	images [--retained-images-file] [--dry-run]	
`
	flag.Parse()
	flag.Set("v", "4")
	flag.Set("alsologtostderr", "true")
	validCommands := []string{"images"}
	if len(os.Args) < 2 {
		glog.Errorf("%s", usage)
		os.Exit(2)
	} else if !_stringInList(validCommands, os.Args[1]) {
		glog.Errorf("Invalid command %s\n%s", os.Args[1], usage)
		os.Exit(2)
	}

	imagesCommand := flag.NewFlagSet("images", flag.ExitOnError)
	retainedImagesListFile := imagesCommand.String("retained-images-file", "", "Retained images list file")
	imageRetainPeriod := imagesCommand.Int64("image-retain-period", 86400, "image retain period")

	dryRun = imagesCommand.Bool("dry-run", false, "dry run - only print actions")

	switch os.Args[1] {
	case "images":
		imagesCommand.Parse(os.Args[2:])
		imagesCommand.Set("v", "4")
	default:
		glog.Errorf("%q is not valid command.\n", os.Args[1])
		os.Exit(2)
	}

	if os.Getenv("CLEANER_DRY_RUN") != "" {
		*dryRun = true
	}

	glog.Infof("\n----------------\n Started dind-cleaner")

	glog.Infof("First verson - only image cleaner. "+
		"retainedImagesListFile = %s "+
		"retainedImagesPeriod = %d "+
		"dry-run = %t", *retainedImagesListFile, *imageRetainPeriod, *dryRun)

	retainedImagesList, err := readFileLines(*retainedImagesListFile)
	if err != nil {
		glog.Errorf("Failed to read file %s: %v", *retainedImagesListFile, err)
	}
	cleanImages(retainedImagesList, *imageRetainPeriod)
}
