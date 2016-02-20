# TF2-MvM-Bot-Control

Dependencies

TF2 Items - https://builds.limetech.org/?project=tf2items

TF2 Atttributes - https://github.com/FlaminSarge/tf2attributes

TF2] 10vM (Ten Mann vs Machine) - https://forums.alliedmods.net/showthread.php?p=1819189

Install the latest versions of the above and get them working.

Compile Bot Control, drop the smx file into your plugins folder, job done.



Mission Files

Embed 'vip' into the bot name and only players with custom flag 1 can control the bot.

Embed 'block' into the bot name to stop any player from controlling it.


As an example:

TFBot

{

  Class Sniper
  
  name "blockAccurately Sniper"
  
...
  
}


 It can go at the beginning, middle or end and it isn't case sensitive, same for vip.

