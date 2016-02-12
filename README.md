# TF2-MvM-Bot-Control

Dependencies

TF2 Items - https://builds.limetech.org/?project=tf2items

TF2 Atttributes - https://github.com/FlaminSarge/tf2attributes

Install the above and get them working.

Compile Bot Control, drop the smx file into your plugins folder, job done.



Mission Files

Embed 'vip' into the bot name and only players with custom flag 1 can control the bot.

Embed 'block' into the bot name to stop any player from controlling it.

(You don't need the quote marks.)

As an example:

TFBot
{

  Class Sniper
  
  name "blockAccurately Sniper"
  
  Health 130
  
  Skill Expert
  
  Attributes AlwaysCrit
  
  WeaponRestrictions PrimaryOnly
  
  CharacterAttributes
  
  {
  
    "move speed bonus"	0.0
    
    "damage bonus"         1.0
    
    "sniper charge per sec"     5.0
    
  } 
  
}


 It can go at the beginning, middle or end and it isn't case sensitive, same for vip.
