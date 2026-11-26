#import "DGPreferences.h"
double DGHoldSpeed(void){double speed=[NSUserDefaults.standardUserDefaults doubleForKey:@"douglass.holdSpeed"];return speed>=1.5&&speed<=3?speed:2;}
void DGRenderDanmaku(UILabel *label,NSString *plain,NSArray *emoticons){
 NSUserDefaults *prefs=NSUserDefaults.standardUserDefaults;CGFloat size=[prefs doubleForKey:@"douglass.danmaku.size"];if(size<12||size>28)size=14;
 NSString *fontName=[prefs stringForKey:@"douglass.danmaku.fontName"];UIFont *font=fontName.length?[UIFont fontWithName:fontName size:size]:nil;
 if(!font){NSInteger style=[prefs integerForKey:@"douglass.danmaku.font"];if(style==2)font=[UIFont monospacedSystemFontOfSize:size weight:UIFontWeightSemibold];else{UIFontDescriptor *descriptor=[[UIFont systemFontOfSize:size weight:UIFontWeightSemibold].fontDescriptor fontDescriptorWithDesign:style==1?UIFontDescriptorSystemDesignRounded:style==3?UIFontDescriptorSystemDesignSerif:UIFontDescriptorSystemDesignDefault];font=[UIFont fontWithDescriptor:descriptor size:size];}}
 NSArray *colors=@[UIColor.whiteColor,UIColor.systemYellowColor,UIColor.systemPinkColor,UIColor.systemCyanColor,UIColor.systemGreenColor];UIColor *color=colors[MIN(4,MAX(0,[prefs integerForKey:@"douglass.danmaku.color"]))];label.font=font;label.textColor=color;
 NSMutableAttributedString *text=[DGRichText(plain,emoticons,font,color)mutableCopy];if([prefs boolForKey:@"douglass.danmaku.stroke"]&&text.length)[text addAttributes:@{NSStrokeColorAttributeName:UIColor.blackColor,NSStrokeWidthAttributeName:@(-3)} range:NSMakeRange(0,text.length)];label.attributedText=text;
 id shadow=[prefs objectForKey:@"douglass.danmaku.shadow"];label.layer.shadowColor=UIColor.blackColor.CGColor;label.layer.shadowOpacity=!shadow||[shadow boolValue]?.85:0;label.layer.shadowRadius=2;label.layer.shadowOffset=CGSizeMake(0,1);
}
