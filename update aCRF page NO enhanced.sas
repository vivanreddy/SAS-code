/*-----------------------------------------------------------------------------
PAREXEL INTERNATIONAL LTD
Sponsor / Protocol No: Macro tool
PXL Study Code: 
SAS Version: SAS 9.3
Operating System: Windows 
-------------------------------------------------------------------------------
Author: Lianbo Zhang $LastChangedBy:  $
Creation / modified: Tuesday, January 26, 2016 11:42:31 / $LastChangedDate: $
Program Location/name: $HeadURL:$
Files Created: This program is to check aCRF annotation's page number and assign them into SDTM spec.
 
Update hisitory:
2016-1-30: special condition: update for VISIT CRF page = null issue
           logical improve : update for the situation "same VARIABLE name but different SUPPDOMAIN"
           program bug : update for miss "file print;" in VARDEF 
2016-8-18: update the QSCAT join part, fix the tail or lead blank issue caused by length, 
           when we are using put(xxx,$fmt.);
2016-8-18: update the QSCAT filter part, fix SUPP var whose IDVAR =  QSCAT ;
2016-9-7 : compress continous blank in annotation at first ( compbl ) ; 
2016-9-7 : add font style check ;
2016-10-18 : modify the period sign after variable name issue eg "xxxxVARNAME." ;
2016-10-18 : some place using translate function replace tranwrd ;
2017-02-28 : add more new QSCAT / QSTEST format ;
2017-02-28 : adjust the filter rule in VALDEF_SUPP ;
2017-02-28 : adjust the filter rule in font style check ;
2017-03-09 : update PAGE column length to char200 ;
2017-07-16 : major update, add nested valdef check,eg, DSCAT, LBCAT.LBSPEC.LEMETHOD.LBTESTCD
2017-07-16 : solve the carrige and return character in annoation issue
2017-07-25 : minor update for actived blank row is VALDEF issue 
2017-11-17 : fix some logic issue in nested VALDEF section
-------------------------------------------------------------------------------
MODIFICATION HISTORY: Subversion $Rev:  $
-----------------------------------------------------------------------------*/


/*  1, please make sure your SDTM spec's  VARORDER <column2> are numeric format*/
/*  2, please make sure your SDTM spec's  VALDEF's VALUEOID and VALVAL are sorted in order */
/*  3, please make sure your SDTM spec's CRF page column is text format*/
/*  4, please backup your orgianl spec, before using this macro*/
/*  5, please make sure your annotation is CRF is clean, and only have text box , no highlight or comments note*/
/*  6, please check your log after running this macro, if have some err0rs, you should pay attention
       usually it is due to your spec columns have different formats, SAS don't support different attribute
       within one variable   */
 
/******************************************************************************/
/*  Suppose your QSTESTCD is uniqued, if not please use another version       */
/******************************************************************************/
/*options nonotes;*/
%let specname=%str(229797 sdtm mapping specifications v1.1_20171103.xlsx);    /*(containing the extend name "XLSX" or other )*/
%let acrf= %str(54767414MMY3009_AnnotatedSDTM_eCRF_V2.0_20171116) ;    /*only file name*/
%let mainrange=%str(B9:S);  /* for old spec it is  B7:S  ;  for new spec it is B9:S   */
%let supprange=&mainrange;


%macro currentroot;
%global currentroot;
%let currentroot= %sysfunc(getoption(sysin));
%if "&currentroot" eq "" %then %do;
%let currentroot= %sysget(SAS_EXECFILEPATH);
%end;
%mend;
%currentroot
%let saswork=%sysfunc(pathname(work));

%let pgmname=  %scan( %str(&currentroot),-1,\) ; 
%let root=%substr(%str(&currentroot),1,%eval(%index(%str(&currentroot), %str(&pgmname))-1));
%put &root ;

/*  Environment */

options  VALIDMEMNAME=EXTEND;
filename  annotate "&root.&acrf..xfdf"  ;
filename  SXLEMAP "&root.annotation.map";
libname   annotate xmlv2 xmlmap=SXLEMAP access=READONLY;
proc delete data= _ALL_ ;
run;

DATA freetext; SET annotate.freetext;   freetext_page=freetext_page+1 ; run;
DATA p; SET annotate.p; run;
DATA span; SET annotate.span; run;
data annotation;
length annotation $5000 ;
  merge p span ;
  by p_ORDINAL;
  freetext_ORDINAL= body_ORDINAL ;
  annotation= catx(' ', p, span);
run;

proc transpose data =annotation out=annotation1(drop=_:) prefix=annovar;
  by freetext_ORDINAL ;
  var annotation;
run;


PROC CONTENTS 
	directory  				
	DATA=annotation1	    
	position   noprint             
	out=ContentsAsDataSet ; 
run;


proc sql noprint;
  select distinct NAME into :annovar separated by ',' from ContentsAsDataSet where NAME like 'annovar%' ;
quit;
%let annovar=&annovar;

data annotation2 ;
  length annotation $5000;
  set annotation1;
  annotation=catx(' ',&annovar);
  keep freetext_ORDINAL annotation;
run;

title "Check annotation font style " ;
data final1 ;
  
file print;
  merge annotation2(in=a keep= freetext_ORDINAL annotation ) freetext (keep=freetext_ORDINAL freetext_subject freetext_page defaultstyle) ;
  by freetext_ORDINAL;
  if a;

  if _n_=1 then do;

/*  font: italic bold Arial 10pt or 12pt; text-align:left; color:#0000FF*/
    re= prxparse('/font:.*italic bold Arial.*1[02].*pt/');
  end;
retain  re  ;

if annotation ne '' and not prxmatch(re,defaultstyle )>0 
     then put  annotation "in page: " freetext_page  " font style is incorrect , please check" ;
drop re ;

  if find(annotation,'NOT SUBMITTED')=0 and 
     find(upcase(annotation),'ANNOTATION')=0 and
     find(upcase(annotation),'NOTE:')=0  and
     find(upcase(annotation),'LINKED TO RELATED')=0 and 
     find(upcase(annotation),'VIA RELREC')=0 
;
/*	remove the annotation such as DM = Demographics etc   */
  if length(annotation)>6 then do ; 
        if   not  (find (compress(annotation),'=')=3 and 
        substr(compress(annotation),1,4) = upcase(substr(compress(annotation),1,4)) and
        substr(compress(reverse(annotation)),1,1) ne upcase(substr(compress(reverse(annotation)),1,1))
     );
  end;
  if freetext_subject in ('Text Box','VOID') or 0<length(freetext_subject)<4 then call missing(freetext_subject); 
  if freetext_subject = '(NO VALUE RECORDED)' then delete; 

run;

data final (drop=count _freetext_subject);
  length _freetext_subject $2000;
  set final1; 
/*  there are multiple VALUE combinaion for one LBTESTCD or --CAT in VALDEF,  we use ^ separate them */
  _freetext_subject= freetext_subject;
  if find(_freetext_subject,'^') then do;
  count=1; 
   do while (scan(_freetext_subject, count, '^') ne '' );
  	 freetext_subject= strip(scan(_freetext_subject, count, '^'));
	 output; 
	 count +1 ; 
   end;
  call missing(count);
  end;
  else output;

run;

title; 

proc sort data= final nodupkey;
by freetext_page freetext_ORDINAL annotation freetext_subject;
run;

data table1;
length temp  $200 VALUEOID_1 $500; 
  set final ;
  annotation= tranwrd(annotation,'= ','=');
  annotation= tranwrd(annotation,' =','=');

/*For DSCAT QSCAT in VALDEF*/
if find(annotation,'CAT')=3 and length(annotation)=5 and ^missing(freetext_subject ) then annotation= catx(' = ',annotation,scan(freetext_subject,-1,'.'));

/*For nested LBCAT.LBSPEC.LBMETHOD.LBTESTCD  in VALDEF*/
/*  very complex                                 */
array LBVAL $400 LBCAT LBSPEC LBMETHOD ;
if find(freetext_subject,'LB')=1 then do;
   count =1 ; 
	LBCAT= '(NO VALUE RECORDED)';
	LBSPEC= '(NO VALUE RECORDED)';
	LBMETHOD= '(NO VALUE RECORDED)';

  do while (scan(freetext_subject, count, '.') ne '' ) ;
   temp= scan(freetext_subject, count, '.') ;
   if find(annotation,'LBTESTCD=' )>0  or find(annotation,'LBORRES' )>0 
     or find(annotation,'LBMETHOD' )>0 or find(annotation,'LBSPEC' )>0
   then do i = 1 to 3 ; 
    if temp= vname(LBVAL[i]) then LBVAL[i]= scan(freetext_subject, count + 1, '.') ; 
   end; 
     count +1 ; 
  end; 



  if find(annotation,'LBTESTCD' )>0  or find(annotation,'LBORRES' )>0 then  VALUEOID_1= catx('.', 'LBCAT', LBCAT, 'LBSPEC', LBSPEC, 'LBMETHOD', LBMETHOD ) ;
  else if find(annotation,'LBMETHOD' )>0 then VALUEOID_1= catx('.', 'LBCAT', LBCAT, 'LBSPEC', LBSPEC);
  else if find(annotation,'LBSPEC' )>0 then VALUEOID_1= catx('.', 'LBCAT', LBCAT);

  if  annotation= 'LBMETHOD' and LBMETHOD ne '(NO VALUE RECORDED)' then annotation= cats('LBMETHOD=',LBMETHOD) ; 
  if  annotation= 'LBSPEC'   and LBSPEC ne '(NO VALUE RECORDED)'  then annotation= cats('LBSPEC=',LBSPEC) ; 

end;

  if  VALUEOID_1 ne '' then freetext_subject= VALUEOID_1 ; 

  annotation= tranwrd(annotation,'= ','=');
  annotation= tranwrd(annotation,' =','=');
  annotation= compbl(annotation);
  annotation= translate(annotation,'','*.');
  annotation= compbl(annotation);

  drop temp count i LBCAT LBSPEC LBMETHOD VALUEOID_1; 
run;

data valdef_supp1 ;
  set table1;
  length VALVAL $100 ;
/*  where compress(annotation) like '%inSUPP__whenIDVAR=%' or */
/*        compress(annotation) like '%inSUPP__whereIDVAR=%';*/
  where compress(annotation) like '%inSUPP__%' ;

  VALVAL= scan(annotation,1,' =');
  var2= substr(annotation, find(annotation,'SUPP'), 6 ) ;
  VALUEOID= catx('.', var2,'QNAM');
  keep VALUEOID VALVAL freetext_page freetext_ORDINAL ;
run;

proc sort data= valdef_supp1 nodupkey;
  by VALUEOID VALVAL freetext_page;
run;

/*suppdomain in VALDEF*/

data valdef_supp;
  length page $200;
  set valdef_supp1;
  by VALUEOID VALVAL freetext_page;
  retain page ;
  if first.VALVAL then call missing(page) ;
  page= catx(', ',page, freetext_page) ;  
  if last.VALVAL;
run;

data valdef_testcd;
  set table1;
  where annotation like  '%TESTCD%' ;
  annotation= tranwrd(annotation,' when ','^');
/*  annotation= tranwrd(annotation,' where ','^');*/
  annotation= tranwrd(annotation,' and ','^');
  array element $200 var1-var5;
   do i= 1 to 5;
      element[i]= scan(annotation,i,'^');
      if find(element[i],'TESTCD=')=0 then call missing(element[i]);
      if element[i] ne '' and (find(element[i],'LB') ne 1 or length(freetext_subject)>25) 
/*and find(element[i],'QS') ne 1 */
    then do ;
        VAR=element[i];
        output;
      end;
   end;
  drop i ;
run;

proc sort data= valdef_testcd nodupkey;
  by freetext_subject VAR  freetext_page ;
run ;

data valdef_testcd_1 /*(where=(find(VALUEOID,'ALL') ne 6))*/;
length page  $200 VALVAL $100;
  set valdef_testcd;
  by  freetext_subject VAR  freetext_page ;
  retain page ;
  _freetext_page= cats(freetext_page) ;
  if first.VAR then call missing(page);
  page= catx( ', ',page,_freetext_page ) ;
  if find(freetext_subject,'LB')=1 then VALUEOID= catx('.', substr(freetext_subject,1,2),freetext_subject,scan(var,1,'=') );
  else VALUEOID= catx('.', substr(var,1,2),scan(var,1,'=') );
  VALVAL=scan(var,2,'=');
  if last.VAR  then output;
  keep VALUEOID VALVAL page freetext_ORDINAL ;
run;



data valdef_CAT ;
  length VALUEOID $200 VALVAL $100;
  set table1;
  where ( ( annotation like  '%QSCAT%' and find(annotation, 'QSSTAT')=0) or
            annotation like  '%DSCAT%'  or
		    annotation like  '%LBCAT%' ) 
        and  annotation not like '%SUPP__ %';
   if find(annotation,'=') >1 then do;  
	   VALUEOID= catx('.',substr(scan(annotation,1,'='),1,2),scan(annotation,1,'='));
	   VALVAL=  scan(annotation,2,'=');
   end;
   else do;
    VALUEOID= catx('.',substr(scan(annotation,1,'='),1,2),scan(annotation,1,'='));
    VALVAL='(NO VALUE RECORDED) in aCRF';
   end;
   drop annotation;
run;

proc sort data= valdef_CAT nodupkey;
  by  VALUEOID  VALVAL freetext_page ;
run ;

%let valdef_LBCATinc=Y;
%let valdef_DSCATinc=Y;
%let valdef_QSCATinc=Y;

title1 "Null VALVAL cross check between VALDEF and aCRF ";
title2 "< ignore this part, if you don't perpare to check nested structure in VALDEF >";

data valdef_CAT1;
  length page $200;
  set valdef_CAT;
  by VALUEOID  VALVAL freetext_page ;
  retain page ;
  file print;
  _freetext_page= cats(freetext_page) ;
  if first.VALVAL then call missing(page);
  page= catx( ', ',page,_freetext_page ) ;
  if last.VALVAL  then do;
    if VALVAL = '(NO VALUE RECORDED) in aCRF' then do; 
      call symputx('valdef_'||strip(scan(VALUEOID,1))||'CATinc', 'N');
	  put VALUEOID "in page " page "is" VALVAL ", need manual check VALUEOID in VALDEF below";
	end;
      output;
  end;
  keep VALUEOID VALVAL page freetext_ORDINAL ;
run;


data valdef_LBSPEC ;
  length VALUEOID $200 VALVAL $100;
  set table1;
   where (annotation like  '%LBSPEC%' or
           annotation like  '%LBMETHOD%'  ) 
        and  annotation not like '%SUPP__ %'  ;
   if find(annotation,'=') >1 then do;  
     VALUEOID= catx('.',substr(scan(annotation,1,'='),1,2),freetext_subject,scan(annotation,1,'='));
     VALVAL=  scan(annotation,2,'=');
   end;
   else do;
     VALUEOID= catx('.',substr(scan(annotation,1,'='),1,2),freetext_subject,scan(annotation,1,'='));
     VALVAL = '(NO VALUE RECORDED) in aCRF';
   end;
/*   drop annotation freetext_subject;*/
run;


proc sort data= valdef_LBSPEC nodupkey;
  by  VALUEOID  VALVAL freetext_page ;
run ;

title1 "Check if LBSPEC or LBMETHOD does not carry enough info" ; 
title2 "< ignore this part, if you don't perpare to check nested structure in VALDEF >";

%let valdef_LBSPECinc=Y;
data valdef_LBSPEC1;
  length page $200;
  set valdef_LBSPEC;
  by VALUEOID  VALVAL freetext_page ;
  retain page ;
  file print;
  _freetext_page= cats(freetext_page) ;
  if first.VALVAL then call missing(page);
  page= catx( ', ',page,_freetext_page ) ;
  if last.VALVAL  then do;
   if VALVAL = '(NO VALUE RECORDED) in aCRF'  then do; 
      call symputx('valdef_LBSPECinc', 'N');
      put VALUEOID " in page " page " is " VALVAL " , need manual check VALUEOID in VALDEF below";
   end;
   else if  count(VALUEOID,'.') <= 2 then do;
	  call symputx('valdef_LBSPECinc', 'N');
      put VALUEOID " in page " page " is " VALVAL " , VALUEOID does not carry enough info";
   end;      
     output;
   end;
  keep VALUEOID VALVAL page freetext_ORDINAL ;
run;

title1; 
title2; 
/*update QSCAT items from latest std_metadata*/

/*libname metadata 'D:\Dropbox\Parexel\Projects\#56022473AML2002\Janssen SDTM metadata\metadata';*/
/*data valdef;*/
/*  set metadata.valdef;*/
/*  where find(VALUEOID,'QSTESTCD')>1 and VALVAL ne 'QSALL';*/
/*  ID= scan(VALLABEL,1,'-');*/
/*  QSCAT=scan(VALUEOID,3,'.'); */
/*if find(QSCAT,"'")=0 then  TEXT= cats("'",QSCAT,"'='", ID, "'");*/
/*else TEXT= cats('"',QSCAT,'"="', ID, '"');*/
/*keep VALUEOID TEXT ; */
/*run;*/

/*proc sort data= valdef out=qscat_fmt nodupkey;*/
/*by VALUEOID;*/
/*run;*/


proc format ;
value $QSCAT
/*put QSCAT to QSTESTCD's prefix*/
'ABC'='ABC01'
'ABI-C'='ABI04'
'ACQ'='ACQ01'
'AD8'='AD801'
'ADCS ADL PREVENTION PARTICIPANT'='AAP1'
'ADCS ADL PREVENTION STUDY PARTNER'='AAP2'
'ADOS2 MOD 1'='ADS1'
'ADOS2 MOD 2'='ADS2'
'ADOS2 MOD 3'='ADS3'
'ADOS2 MOD 4'='ADS4'
'AQRM'='AQR90'
'ARCI 49'='ARCI01'
'ASAS'='ASAS01'
'ASEC'='ASEC1'
'ASEX-FEMALE'='ASEX01'
'ASEX-MALE'='ASEX02'
'ASQOL'='ASQL01'
'AUSCAN NRS'='AUSN01'
'BAI'='BAI01'
'BASDAI'='BASD01'
'BASFI'='BASF01'
'BASMI'='BASM01'
'BDI-II'='BDI02'
'BFI'='BFI01'
'BHS'='BHS01'
'BOND AND LADER VAS'='BLVAS1'
'BOWDLE VAS'='BOWV01'
'BPI SHORT FORM'='BPI2'
'BPIC-SS'='BPIC01'
'BPRS MODIFIED'='BPR90'
'BRISTOL STOOL CHART SCORING'='BSCS90'
'BRISTOL STOOL CHART'='BSC01'
'BSQ'='BSQ01'
'BSS'='BSS01'
'C-SSRS BASELINE'='CSS01'
'C-SSRS BASELINE/SCREENING VERSION'='CSS04'
"C-SSRS CHILDREN'S BASELINE"='CSS06'
"C-SSRS CHILDREN'S SINCE LAST VISIT"='CSS08'
'C-SSRS SCREENING'='CSS09'
'C-SSRS SINCE LAST VISIT'='CSS02'
'CADD'='CADD01'
'CADSS'='CADS01'
'CASI-ANX'='CAS3'
'CAUS'='CAUS90'
'CDAI'='CDAI01'
'CDLQI'='CDLQ1'
'CDR-SB'='CDR04'
'CDR'='CDR01'
'CESD'='CESD01'
'CFI PARTICIPANT'='CFI01'
'CFI STUDY PARTNER'='CFI02'
'CFIA PARTICIPANT'='CFIA90'
'CFIA STUDY PARTNER'='CFIA91'
'CGAA'='CGAA90'
'CGI-C JAPAN'='CGI90'
'CGI-C MDG'='CGI91'
'CGI-SS'='CGISS1'
'CGI'='CGI01'
'CHES-Q BASELINE'='CHSQ90'
'CHES-Q ENDPOINT'='CHSQ90'
'CHES-Q'='CHSQ90'
'CHRT'='CHR01'
'CLASI'='CLAS01'
'CLDQ-HCV'='CLDQ01'
'CPC'='CPC01'
'CPFQ'='CPFQ01'
'CRDPSS'='CRDP01'
'CSQ'='CSQ90'
'CTS'='CTS01'
'CUDOS-A'='CUDOS1'
'DDS17'='DDS01'
'DLQI'='DLQI1'
'DRUG LIKING SCALE'='DLV01'
'DSA'='DSA01'
'DTSQC'='DTSQ02'
'DTSQS'='DTSQ01'
'EASI'='EASI01'
'ECOG'='ECOG1'
'EQ-5D-3L'='EQ5D01'
'EQ-5D-5L'='EQ5D02'
'ETISR-SF'='ETI01'
'EXACT'='EXACT1'
'FACIT FATIGUE'='FACT09'
'FACIT-F'='FACT05'
'FACT-AN'='FACT07'
'FACT-COG'='FACT08'
'FACT-LYM'='FACT02'
'FACT-Leu'='FACT06'
'FACT-P'='FACT04'
'FACT/GOG-NTX'='FACT03'
'FAQ-NACC'='FAQ02'
'FAQ'='FAQ01'
'FLU-IIQ ADDITIONAL'='FLU90'
'FLU-IIQ'='FLU01'
'FLU-PRO ADDITIONAL'='FPRO90'
'FLU-PRO V2 ADDITIONAL'='FPRO91'
'FLU-PRO V2'='FPRO02'
'FLU-PRO'='FPRO01'
'FPGA'='FPGA01'
'FRI INDEX'='FRI01'
'FSS2'='FSS02'
'FTPS'='FTPS01'
'GAD-7'='GAD01'
'GDS SHORT FORM'='GDS02'
'GDS'='GDS01'
'GOAL'='GOAL90'
'GSQS'='GSQS01'
'HADS'='HADS01'
'HAM-A'='HAMA1'
'HAMD 17'='HAMD1'
'HAQ-DI'='HAQ01'
'HCV SIQ V4'='HSIQ02'
'HFPGA'='HFPG01'
'HIS ROSEN'='HISR01'
'IBDQ'='IBDQ01'
'IDS-C SIGH'='IDS09'
'IDS-C'='IDS01'
'IDS-SR'='IDS02'
'IES V2'='IES01'
'IES-R'='IESR01'
'IGA-AD'='IGAAD1'
'IGA'='IGA90'
'IMRS CLIENT'='IMRS01'
'ISI'='ISI01'
'IVAS'='IVAS90'
'IWQOL-LITE'='IWQL02'
'JDA SEVERITY INDEX'='JDA01'
'KATZ-ADL'='KATZ01'
'KPS SCALE'='KPSS'
'KSS'='KSS01'
'LSAS'='LSAS1'
'LSEQ'='LSEQ1'
'MADRS'='MADR01'
'MASES'='MASES1'
'MCTSQ'='MCTSQ9'
'MDASI'='MDA01'
'MDR-TB SOURCE CASE'='MDRTB1'
'MELD'='MELD90'
'MGH ATRQ ADULT'='ATRQ01'
'MGH ATRQ GERIATRIC'='ATRQ02'
'MINI 7 MDD'='MINI90'
'MINI 700'='MINI01'
'MINI KID'='MINI02'
'MINI-MAJOR DEPRESSIVE EPISODE CURRENT'='MI91'
'MOAAS'='MOAA01'
'MOD MFSAF 1W AVERAGE'='MFSA92'
'MODIFIED MFSAF 24H'='MFSA90'
'MODIFIED MFSAF 7D'='MFSA91'
'MOS SLEEP REVISED'='MOSS02'
'MOS SLEEP SCALE'='MOSS01'
'MRS'='MRS01'
'NAPSI'='NAPS01'
'NPGA'='NPGA90'
'NSQ'='NSQ90'
'NTQ'='NTQ90'
'P-FIBS'='PFIB01'
'PABP'='PABP90'
'PAIN NRS OA'='PNRS90'
'PAM-13'='PAM01'
'PAP'='PAP90'
'PAQ'='PAQ01'
'PARTICIPANT EXPECTATIONS BASELINE'='PEI90'
'PASI'='PASI01'
'PDQ'='PDQ01'
'PDQS'='PDQS01'
'PDSS'='PDSS01'
'PGA OA'='PGAOA9'
'PGA PP'='PGAP90'
'PGAA'='PGAA90'
'PGAD PATIENT'='PGAD91'
'PGAD PHYSICIAN'='PGAD91'
'PGIC MDS'='PGIC92'
'PGIC MF'='PGIC91'
'PGIC-Q MDG'='PGIC94'
'PGIC-S MDG'='PGIC93'
'PGICA'='PGICA90'
'PGISD'='PGIS90'
'PHQ-9'='PHQ01'
'POMS 2-A'='POMS03'
'POMS BF'='POMS01'
'POMS'='POMS02'
'PPIGA'='PPIGA90'
'PPPASI'='PPPA01'
'PPSI'='PPSI01'
'PROMIS SF V1 FATIGUE 7A'='PRPH06'
'PROMIS SF V1 FATIGUE 8A PARTICIPANT'='PRPH08'
'PROMIS SF V1 PAIN INTERFERENCE 6B'='PRPH13'
'PROMIS SF V1 PAIN INTERFERENCE 8A PARTICIPANT'='PRPH15'
'PROMIS SF V1 SLEEP DISTURBANCE 8A PARTICIPANT'='PRPH26'
'PROMIS-29 PROFILE V2 PARTICIPANT'='PROM02'
'PSGA'='PSGA90'
'PSQ'='PSQ90'
'PSQI'='PSQ1'
'PSS'='PSS01'
'PSSD'='PSSD90'
'PWC'='PWC01'
'Q-LES-Q-SF'='QLES01'
'QIDS-C'='QIDS01'
'QIDS-SR'='QIDS02'
'QIDS-SR10'='QIDS03'
'QIDS-SR14'='QIDS90'
'QLDS'='QLDS01'
'QLQ-C30'='QLQ01'
'QLQ-MY20'='QLQ02'
'QLQ-PR25'='QLQ03'
'QUALMS'='QLMS01'
'RAPID3'='RAP01'
'RBS-R'='RBSR01'
'RI-PRO ADDITIONAL'='RPRO91'
'RI-PRO'='RPRO01'
'RLCST'='RLCS01'
'RRS'='RRS01'
'RSME'='RSME01'
'S-LANSS'='SLAN01'
'SATE'='SAT90'
'SCORAD'='SCOR1'
'SDS'='SDS01'
'SF36 V2 STANDARD'='SF363'
'SF36 v2 ACUTE'='SF364'
'SHAPS'='SHPS01'
'SHIM'='SHIM01'
'SIA'='SIA90'
'SIAQ POST SELF-INJECTION'='SIAQ2'
'SIAQ PRE SELF-INJECTION'='SIAQ1'
'SIGHD'='SIGHD1'
'SIGMA MADRS'='MADR02'
'SLEEP QUALITY'='SLEE90'
'SLEEPINESS VAS'='SLVAS1'
'SRS-2 ADULT'='SRS203'
'SRS-2 PRESCHOOL'='SRS201'
'SRS-2 SCHOOL AGE'='SRS202'
'SSIGA'='SSIGA90'
'STAI'='STAI01'
'STANFORD SLEEPINESS'='STAN01'
'STOP BANG'='STOP01'
'TANN01'='TANN01'
'TANN02'='TANN02'
'TAQ'='TAQ90'
'TASQ'='TASQ90'
'TNOSS'='TNOSS1'
'TNSN'='TNSN1'
'TSQM-9'='TSQM01'
'TSQM-IV RA'='TSQM90'
'UAL'='UAL90'
'VABS II INTERVIEW'='VAB01'
'VFQ-25 INTERVIEWER ADMINISTERED'='VFQ1'
'VPAI'='VPAI01'
'WHODAS 12-ITEM INTERVIEWER'='WDS01'
'WHODAS 12-ITEM SELF'='WDS02'
'WLQ SF'='WLQ02'
'WLQ'='WLQ01'
'WOMAC NRS'='WOMN01'
'WPAI-GH'='WPAI02'
'WPAI-SHP'='WPAI01'
'WURSS ADD'='WURS90'
'WURSS-21'='WURS01'
'ZBI-22'='ZBI01'
;
RUN;

proc sql noprint;
  create table valdef_testcd_2 as
   select a.*, b.VALVAL as VALCAT, b.VALUEOID as VALUEOID_cat
   from valdef_testcd_1 as a 
   left join  valdef_CAT(where=(VALUEOID='QS.QSCAT')) as b
   on  find(strip(a.VALVAL), strip(put(b.VALVAL , $QSCAT.)))=1 
 ;
quit;

data valdef_testcd_3;
  set valdef_testcd_2;
  if find(VALUEOID_cat,'.') ne 3 then VALUEOID= catx('.',VALUEOID_cat, VALCAT, VALUEOID ) ;
  else VALUEOID= catx('.',VALUEOID_cat, VALCAT, scan(VALUEOID,2,'.')) ;
  drop VALCAT VALUEOID_cat;
run;

/*if one item in category is not fully add free text in textbox's subject, 
  then the whole category will cancel the check*/
%macro setvaldef;
data valdef;
length page VALUEOID $200;
  set valdef_testcd_3 valdef_supp  valdef_CAT1 
  %if &valdef_LBSPECinc=Y   %then %str( valdef_LBSPEC1) ;
    ;
  where VALUEOID ne '' 
  %if  &valdef_LBCATinc=N %then %str( and VALUEOID ne 'LB.LBCAT' );
  %if  &valdef_DSCATinc=N %then %str( and VALUEOID ne 'DS.DSCAT' );
  %if  &valdef_QSCATinc=N %then %str( and VALUEOID ne 'QS.QSCAT' );
    ;
  keep VALUEOID VALVAL page freetext_ORDINAL ;
run;
%mend;

%setvaldef



proc sort data= valdef nodupkey;
  by VALUEOID VALVAL page ;
run;

/*vardef main*/
data vardef1;
  set table1;
  annotation1= translate(annotation,'^','[]');
  annotation1= tranwrd(annotation1,' when ','^');
/*  maybe we should remove where*/
/*  annotation1= tranwrd(annotation1,' where ','^');*/
  annotation1= tranwrd(annotation1,' and ','^');
  annotation1= tranwrd(annotation1,' in ','^');
  annotation1= tranwrd(annotation1,'=NOT DONE','');
  annotation1= tranwrd(annotation1,', ',',');
  annotation1= tranwrd(annotation1,' ,',',');
  annotation1= compbl(annotation1);
  drop freetext_subject; 
run;

title "Variable name check finding" ;
data vardef2 ;
  set vardef1;
  file print;
  array element $30 var1-var30;
  do i = 1 to 30 ;
  element[i]=strip(scan(annotation1,i,',^'));
  if find(element[i],'SUPP')=1 then VAR= element[i] ;
  if find(element[i],'=')>0 then element[i]= scan( element[i], 1,'=') ;
    if upcase(element[i]) ne element[i] then call missing(element[i]);
/*  20160607  lianbo add for COVAL in CO when IDVAR=TRGRPID issue*/
    if length(element[i])<3 then call missing(element[i]) ;
/**/
    if  1< find(element[i], ' ')< length(element[i])  then call missing(element[i]) ;

    if length(element[i])>8 then put "w!arn_ing variable "   annotation " length more than 8 char" ;
  end;

run;
title;

 data vardef3;
  set vardef2;
  array element $30 var1-var30;
  if VAR ne '' then output;
  else if VAR = '' and cmiss(of var1-var30) ne 30 then do ;
   do i = 1 to 30 ;
   call missing(VAR);
     if element[i] ne '' then do ;
       VAR= element[i] ;
       output;
     end;
   end;
  end;
keep freetext_: var ;
  run;

proc sort data= vardef3 nodupkey;
  by VAR  freetext_page;
run;

data vardef_main1 ;
length var1 var3 $8 ;
  set vardef3;
   if VAR not in( 'IDVAR') and find(VAR,'SUPP')=0;
  if VAR in('SUBJID','RFICDTC','DTHDTC','BRTHDTC','AGE','AGEU','SEX','RACE','ETHNIC','ARM','DMDTC','ARMCD')
  then VAR1='DM';
  else VAR1=substr(var,1,2) ;
  VAR3=VAR;

  keep VAR1 VAR3 freetext_: ;
run;

proc sort data= vardef_main1 nodupkey;
  by var1 var3 freetext_page ;
run;

data vardef_main;
length page $200 ;
retain page;
  set vardef_main1;
  by var1 var3 freetext_page ;
  if first.var3 then call missing(page);
  page= catx(', ' , page, freetext_page);
  if last.var3 then output;
  drop freetext_page ;
run;


/*vardef supp*/
data vardef_supp1;
length F1 $8 ;
  set Valdef_supp1;
  F1= scan(VALUEOID,1) ;
  _page= freetext_page;
/*  drop page;*/
run;

proc sort data= vardef_supp1 nodupkey;
  by F1 _page ;
run;

data vardef_supp2;
length page $200 ;
retain page;
  set vardef_supp1;
  by F1 _page ;
  if first.F1 then call missing(page);
  page= catx(', ' , page, _page);
  if last.F1 then output;
  drop _page VALUEOID  VALVAL;
run;

data vardef_supp;
length F3 $8;
	set vardef_supp2;
	F3= 'QLABEL' ; output;
	F3= 'QVAL';output;
run;

/*read spec*/

libname SDTMSPEC "&root.&specname" header=no SCAN_TEXT=NO ;

data Define_DATADEF;
  set SDTMSPEC.'Define_DATADEF$B6:D'n ;
  where F2 ne '';
run;
options mprint;
proc sql noprint;
  select distinct var1 into :maindomains separated by " " from Vardef_main ;
  select count( distinct var1) into :mainnum separated by " " from Vardef_main  ;
  select  distinct F1  into :suppdomains separated by " " from  Vardef_supp2; 
  select  count( distinct F1) into :suppnum separated by " " from Vardef_supp2; 
quit;

%let maindomains= &maindomains ;
%let suppdomains= &suppdomains ;
%put &=maindomains;
%put &=suppdomains;


/*do the valdef sheet*/
proc sql noprint;
  create table temp(where=(F1 is not missing))  as
  select page ,  F1,F2, F9     
  from SDTMSPEC.'VALDEF$A2:O'n as a
  left join  valdef as b on a.F1= b.VALUEOID AND a.F2= b.VALVAL 
;
quit;

title "VALDEF page check finding" ;
DATA SDTMSPEC.'VALDEF$A2:O'n;
 MODIFY SDTMSPEC.'VALDEF$A2:O'n  temp;
 file print;
 by F1 F9;
 if page ne '' then do ;
  if page ne F14 and find(F8,'CRF')>0 then  do ;
   put F1 '  ' F2 "aCRF page=  " F14 ' is changed to ' page ;
   F14=page;
  end;
 end;
 else do ;
   if find(F8,'CRF')>0 then do ;
   put  F1 '  ' F2 "aCRF page need check manually" ; 
   end;
 end;
RUN;
title;

/*do the vardef main domain*/
%macro loop_vardef_main ;

 %do i= 1 %to &mainnum ;

title "VARDEF Domain: %scan(&maindomains,&i)" ;

data temp_%scan(&maindomains,&i) ;
  set SDTMSPEC."%scan(&maindomains,&i)$%trim(&mainrange)"n (dbSasType=(F1=char8 F2=numeric F3=char8 ));
  where  F3 is not missing;
run;

 proc sql noprint;
  create table temp2_%scan(&maindomains,&i)(where=(F1 is not missing))  as
  select page, F1 ,F2 , F3  
  from temp_%scan(&maindomains,&i) as a
  left join  vardef_main as b on a.F1= b.VAR1 AND a.F3= b.VAR3 
;
quit;

proc sort data=temp2_%scan(&maindomains,&i) (where= (F3 ne ''));
	by F1 F2;
run;

DATA SDTMSPEC."%scan(&maindomains,&i)$%trim(&mainrange)"n (where= (F3 is not missing) );
 MODIFY SDTMSPEC."%scan(&maindomains,&i)$%trim(&mainrange)"n (where= (F3 is not missing)
     dbSasType=( F18=char200 F2=numeric F1=char8 F6=numeric  F3=char8 )  )  
     temp2_%scan(&maindomains,&i);
   file print;
 by F1 F2;
 if page ne '' then do ;
  if page ne F18 and find(F9,'CRF')>0 then do ;
     put 'VARDEF  ' F1 '  ' F3 "aCRF page=  " F18 ' is changed to ' page ;
     F18=page;
  end;
 end;
 else do ;
   if find(F9,'CRF')>0 and F3 ne 'VISIT' then do ;
    put 'VARDEF  ' F1 '  ' F3 "aCRF page need check manually" ;
   end; 
 end;

RUN;

proc datasets library=work NOlist;
delete temp2_%scan(&maindomains,&i) temp_%scan(&maindomains,&i) ;
quit;

%end;
title;
%mend;
%loop_vardef_main


/*do the vardef main domain*/
%macro loop_vardef_supp ;

 %do i= 1 %to &suppnum ;

title "VARDEF SUPPDOMAIN: %scan(&suppdomains,&i)" ;

DATA SDTMSPEC."%scan(&suppdomains,&i)$%trim(&supprange)"n (where =( F3 in ('QVAL','QLABEL')) );
 MODIFY SDTMSPEC."%scan(&suppdomains,&i)$%trim(&supprange)"n (where =( F3 in ('QVAL','QLABEL'))
     dbSasType=( F18=char200  F3=char8 )  )  
     vardef_supp (drop =freetext_ORDINAL where =(F1 ="%scan(&suppdomains,&i)")) ;
 file print;
 by F3;
 if page ne '' then do ;
  if page ne F18 and find(F9,'CRF')>0  then do ;
     put 'VARDEF  ' F1 '  ' F3 "aCRF page=  " F18 ' is changed to ' page ;
     F18=page;
  end;
 end;
 else do ;
   if find(F9,'CRF')>0 then do ;
   put 'VARDEF  ' F1 '  ' F3 "aCRF page need check manually" ; 
   end;
 end;
RUN;
%end;
title;
%mend;

%loop_vardef_supp

libname SDTMSPEC clear;
libname annotate clear;
filename _all_ clear; 
