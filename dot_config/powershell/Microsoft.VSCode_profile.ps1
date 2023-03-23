#Temporary for new console
$PROJECT = $PWD
if (Get-Command 'Import-CommandSuite' -ErrorAction SilentlyContinue) {
    Import-CommandSuite
}
