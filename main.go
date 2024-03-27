package main

import (
    "fmt"
	"os"
    "os/exec"
	"path/filepath"
    "bufio"
    "time"
    "strings"
)

var root string = ""


func main() {

	exe, err := os.Executable()
	root = filepath.Dir(exe)
    currentPolicy := setPolicy("RemoteSigned")

    // set ExecutionPolicy to remote


    // Define the PowerShell script path
    scriptPath := root+"\\pxeboot.ps1"

	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
        fmt.Println("Error cant find file pxeboot.ps1 at:", scriptPath)
        logger("Error cant find file pxeboot.ps1")
		panic(err) 
	}	

    // Define the PowerShell command to execute the script
    cmd := exec.Command("powershell.exe", "-File", scriptPath)

    // Execute the PowerShell command
    output, err := cmd.CombinedOutput()
    if err != nil {
        fmt.Println("Error executing PowerShell script:", err)
        logger("Error executing PowerShell script")
        panic(err) 
    }

    // Print the output of the PowerShell script
    fmt.Println(string(output))
    logger(string(output))

    setPolicy(currentPolicy)
}


func logger(msg string){

	filePath := root+"\\log.txt"

    // Open the file in append mode. If the file doesn't exist, it will be created
    file, err := os.OpenFile(filePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
    if err != nil {
        fmt.Println("Error opening the file:", err)
        logger("Error opening the file")
    }
    defer file.Close()

    // Create a writer for the file
    writer := bufio.NewWriter(file)

    // Write a new line to the file
    _, err = writer.WriteString(timeStamp() + ": "+toASCII(msg)+"\n") // The \n is the newline character
    if err != nil {
        fmt.Println("Error writing to the file:", err)
        logger("Error writing to the file")
        return
    }

    // Flush the buffer to ensure all data is written to the file
    err = writer.Flush()
    if err != nil {
        fmt.Println("Error flushing the buffer:", err)
        logger("Error flushing the buffer")
        return
    }

}


func timeStamp() string{
	time := time.Now().Format("2006-01-02 15:04:05")
	return time
}


func toASCII(s string) string {
    var asciiStr string
    for _, r := range s {
        if r <= 127 {
            asciiStr += string(r)
        } else {
            // Replace non-ASCII character with '?'
            // or you can just skip it with `continue`
            asciiStr += "?"
        }
    }
    return asciiStr
}

func setPolicy(policy string) string{

    // Check current execution policy
    policyCmd := exec.Command("powershell", "-Command", "Get-ExecutionPolicy")
    policyOutput, err := policyCmd.Output()
    if err != nil {
        fmt.Println("Error checking execution policy:", err)
        logger(string("Error checking execution policy:"+err.Error()))
        return "Error"
    }

    currentPolicy := strings.TrimSpace(string(policyOutput))
    fmt.Println("Current execution policy:", currentPolicy)
    logger(string("Current execution policy:"+currentPolicy))

    // Set execution policy (for example, to RemoteSigned)
    setPolicyCmd := exec.Command("powershell", "-Command", "Set-ExecutionPolicy "+policy+" -Scope CurrentUser -Force")
    if err := setPolicyCmd.Run(); err != nil {
        fmt.Println("Error setting execution policy:", err)
        logger(string("Error setting execution policy"+err.Error()))
        return ""
    }
    fmt.Println("Execution policy set to "+policy)
    logger(string("Execution policy set to "+policy))
    return currentPolicy
    

}