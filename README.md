# SwapBackground
## Goals:
1. Create Dir Of Wallpapers
2. Upload images to dir on github
3. Pull images down to specific locations based on machine arch
4. Change Wallpapers Programmatically:
    - create wallpapers path
        - if it does not exist - git clone wallpapers into place
    - select random pic from dir
    - parse settings.json
    - parse backgound image of specific profile
    - change to new img path
    - rewrite entire file
