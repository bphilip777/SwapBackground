# SwapBackground
## Goals:
1. Create Dir Of Wallpapers
2. Upload images to dir on github
3. Pull images down to specific locations based on machine arch
4. Change Wallpapers Programmatically:
    - create wallpapers path
        - if it does not exist - git clone wallpapers into place
    - select random pic from dir
    - parse settings.json into tree
    - walk tree -> swap backgroundImage node for new image
    - write tree
5. Add powershell commands to run fn:
    - $Action = TaskAction "SwapBackground"
    - $Trigger = Schedule-Task -Daily -9:00Am
    - Schedule
5. Add os commands to run automatically:
    A. On Windows:
        -action: $Action = New-ScheduledTaskAction -Execute "path\to\code"
        -trigger: $Trigger = New-ScheduledTaskTrigger -Daily -At 9:00Am
        -register: Register-ScheduledTask -TaskName "Name-Of-Task" -Action $Action -Trigger $Trigger
        -unregister: Unregister-ScheduledTaks -TaskName "Task-Name" -Confirm:$false
        -get: Get-ScheduledTask
        -combo: Get-ScheduledTask | Where-Object {$_.TaskName -eq "Task-Name"} | Unregister-ScheduledTask -Confirm:$false
    B. On Linux:
    C. On Macos:
