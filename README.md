# TF2-MvM-Bot-Control

Dependencies

TF2 Items - https://builds.limetech.org/?project=tf2items

TF2 Atttributes - https://github.com/FlaminSarge/tf2attributes

Install the latest versions of the above and get them working.

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
 
 Also, this doesn't block the last bot in a wave or trap the end of a wave, so be sure to block the last bot in any wave because if you try to control it then the wave will end prematurely.
 
 If you trap the end of a wave then a human could just troll from spawn. You could devise a countermeasure but I always liked the fact the mission maker would have to account for it....plus it was easier :)
