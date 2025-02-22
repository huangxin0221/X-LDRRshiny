# Load packages ----
conf=read.table("X-LD.conf", as.is = T)

# install.packages(c("shiny","bsplus","RColorBrewer","corrplot"))
library(shiny)
library(bsplus)
library(reshape2)
library(ggplot2)
library(data.table)
library(zip)
source("helper.R")
unzip("plink2.zip",overwrite=T) 
if(length(grep("linux",sessionInfo()$platform, ignore.case = TRUE))>0) {
  print("linux")
  system("chmod a+x ./plink2_linux")
  plink2 = "./plink2_linux"
} else {
  print("apple")
  system("chmod a+x ./plink2_mac")
  plink2 = "./plink2_mac"
  #system("git rev-list head --max-count 1 > gitTag.txt")
}

options(shiny.maxRequestSize=conf[1,2]*1024^2, shiny.launch.browser=T)
gTag=read.table("gitTag.txt")

# Define UI for X-LD Application
ui <- fluidPage(
        theme = "style.css",
        div(style = "padding: 1px 0px; width: '100%'",
        titlePanel(
          title = "",
          windowTitle = "X-LD-Plus"
        )
      ),
      navbarPage(
        title = div(
          span(
            HTML("<input type=button style='font-size:30px;border:0;height:35px' value='X-LD-Plus' onclick=\"window.history.go(-1)\">"),
            style = "position: relative; top: 30%; transform: translateY(-50%);"
          )
        ),
        id = "inNavbar",
        tabPanel(
          title = "Data Input",
          value = "datainput",
          fluidRow(
            column(
              4,
              fileInput(
                "file_input",
                paste0('Source files (.bim, .bed, .fam) [< ', conf[1,2],' MB]'),
                multiple = TRUE,
                accept = c("bed", "fam", "bim")
              ) %>%
              shinyInput_label_embed(
                icon("question-circle") %>%
                bs_embed_popover(
                  title = "The chromosome index (the first column of the .bim file) must be numeric", content = "", placement = "right"
                )
              )
            ),
            column(
              4,
              numericInput('autosome', "Autosome number", value=22)
            ),
            column(
              4,
              radioButtons(
                'bred',
                'Population type',
                choices = list('Outbred' = 'outbred', 'Inbred' = 'inbred'),
                selected = 'outbred'
                #inline = T
              ) %>%
                shinyInput_label_embed(
                  icon("question-circle") %>%
                    bs_embed_popover(
                      title = "INBRED is chosen if your sample has homogenous genome, otherwise choose OUTBRED", content = "", placement = "right"
                    )
                )
            )
          ),
          hr(),
          fluidRow(
            column(
              4,
              sliderInput(
                'maf_cut',
                'MAF threshold',
                 value = 0.05, min = 0.01, max = 0.1, step = 0.01
              ) %>%
              shinyInput_label_embed(
                icon("question-circle") %>%
                bs_embed_popover(
                  title = "Marker with allele frequency lower than the given MAF threshold will be filtered out", content = "", placement = "right"
                )
              )
            ),
            column(
              4,
              sliderInput(
                'geno_cut',
                'Missing genotype rates',
                value = 0.2, min = 0, max = 1, step = 0.1
              ) %>%
              shinyInput_label_embed(
                icon("question-circle") %>%
                bs_embed_popover(
                  title = "Marker with missing call rates exceeding the provided value will be filtered out", content = "", placement = "right"
                )
              )
            ),
            column(
              4,
              sliderInput(
                'proportion',
                'Marker sampling proportion',
                value = 1, min = 0.2, max = 1, step = 0.2
              ) %>%
                shinyInput_label_embed(
                  icon("question-circle") %>%
                    bs_embed_popover(
                      title = "A proprotion of the whole genome markers are sampled for X-LD analysis", content = "", placement = "right"
                    )
                )
            )            
            
          ),
          hr(),
          fluidRow(
            column(
              4,
              numericInput('times', "B (the round of iterations)", value="100") %>%
              shinyInput_label_embed(
                icon("question-circle") %>%
                bs_embed_popover(
                  title = "When B≈100, sufficient accuracy can be guaranteed for medium-sized samples (~5000).", content = "", placement = "right"
                )
              )
            )
          ),
          fluidRow(
            column(
              4,
              actionButton(
              'run',
              'Run (X-LD-Plus)!'
              )
            )
          )
        ),
        tabPanel(
          title = "Visualization",
          value = "visualization",
          fluidRow(
            column(12, 
              mainPanel(
                tabsetPanel(
                  id = 'X-LDFunctions',
                  type = 'tabs',
                  tabPanel(
                    'chromosome level LD',
                    plotOutput('me'),
                    htmlOutput('me_note')
                  ),
                  tabPanel(
                    'chromosome level LD (scaled)',
                    plotOutput('me_scale'),
                    htmlOutput('me_scale_note')
                  )
                 )
              )
            )
          ),
          hr(),
          fluidRow(
            column(
              12,
              mainPanel(
                column(3,
                  downloadButton(
                    'figure', 
                    'Figure'
                  )
                ),
                column(3,
                  downloadButton(
                    'LD', 
                    'Table'
                  )
                )
              )
            )
          )
        ),
        tabPanel(
          title = "About",
          value = "about",
          tags$h3("Source Code"),
          tags$p(HTML("For X-LD-Plus core algorithm implementation and R Shiny code in this web tool please refer to")),
          tags$p(HTML("<a href=\"https://github.com/huangxin0221/X-LD-PlusRshiny\" target=\"_blank\">GitHub repository: X-LD-PlusRshiny.</a>")),
          tags$br(),
          tags$h3("Citation"),
          tags$p(HTML("<a>Xin Huang et al, Scalable computing for LD spectra across species (Under review).</a>")),
          tags$br(),
          tags$p(HTML(paste("Git version:", gTag[1,1])))
      
        )
      )
)

# Define server logic required to draw a histogram

server <- function(input, output, session) {
  # Plot on the web
  currentFile <- reactive({
    withProgress(message="X-LD:", value=0, {
      incProgress(1/3, detail = paste0(" check filesets ..."))
      FileLoad=0
      str=""
      if(length(which(grepl("*.bed", input$file_input$name)))  != 1) {
        str=paste(str, "No bed file found.") 
      } else {
        FileLoad=FileLoad+1
      }
      
      if(length(which(grepl("*.bim", input$file_input$name)))  != 1) {
        str=paste(str, "\nNo bim file found.")
      } else {
        FileLoad=FileLoad+1
      }
      
      if(length(which(grepl("*.fam", input$file_input$name)))  != 1) {
        str=paste(str, "\nNo fam file found.")
      } else {
        FileLoad=FileLoad+1
      }
      
      if (FileLoad < 3) {
        showNotification(str, duration = 5, type = "error")
        return()
      } else if (FileLoad > 3) {
        showNotification("More than 3 files selected", duration = 5, type="error")
      }
      
      idx=grep(".bed$", input$file_input$datapath)
      if (length(idx)==1) {
        rt=substr(input$file_input$datapath[idx], 1, nchar(input$file_input$datapath[idx])-4)
      }
      for (i in 1:3) {
        if (i != idx) {
          f1 = input$file_input$datapath[i]
          tl = substr(f1, nchar(f1)-2, nchar(f1))
          file.symlink(f1, paste0(rt, ".", tl))
        }
      }
            
      incProgress(1/3, detail = paste0(" check chromosome ..."))
      froot = substr(input$file_input$datapath[idx], 1, nchar(input$file_input$datapath[idx])-4)
      get_chr = read.table(paste0(froot,'.bim'),header=F,colClasses = c("character","NULL","NULL","NULL","NULL","NULL"))
      if (length(which(is.na(as.numeric(get_chr[,1]))))>0){
        showNotification("The chromosome index in the .bim file must be numeric!", duration = 5, type="error")
        stop("The chromosome index in the .bim file must be numeric! Refresh to continue.")
      }
      
      incProgress(1/3, detail = paste0(" data pre-filter ..."))
      
      QC1 = paste0(plink2, " --bfile ", froot, " --chr-set ", input$autosome, " --allow-extra-chr --set-missing-var-ids @:# --autosome --snps-only --make-bed --out ", froot,".1.autosome.snp")
      cat("QC...\nExtract autosome SNP variants...\n\n")
      system(QC1)
      
      if (as.numeric(input$proportion)==1){
        QC2 = paste0(plink2, " --bfile ", froot, ".1.autosome.snp --rm-dup force-first --chr-set ", input$autosome, " --maf ", input$maf_cut, " --geno ", input$geno_cut, " --make-bed --out ", froot,".3.core")
        cat("\nQC...\nMAF and missing rate...\n\n")
        system(QC2)
        cat("\nQC...\nFinished...\n\n")
        frootCore = paste0(froot,".3.core")
      }else{
        QC2 = paste0(plink2, " --bfile ", froot, ".1.autosome.snp --rm-dup force-first --chr-set ", input$autosome, " --maf ", input$maf_cut, " --geno ", input$geno_cut, " --make-bed --out ", froot,".2.maf.geno")
        cat("\nQC...\nMAF and missing rate...\n\n")
        system(QC2)
        #mm=as.numeric(strsplit(system(paste0("wc -l ", froot, ".2.maf.geno.bim"),intern=T)," ")[[1]][1])
        #M=(input$proportion)*mm
        Thin_CMD = paste0(plink2, " --bfile ",froot,".2.maf.geno --chr-set 90 --allow-extra-chr --allow-no-sex --thin ",input$proportion, " --make-bed --out ",froot,".3.core")
        cat("\nThin...\n")
        system(Thin_CMD)
        
        frootCore = paste0(froot,".3.core")
      }

      return (frootCore)
    })
  })
  
  mark <- gsub('[-: ]','',as.character(Sys.time()))
  
  observeEvent(input$run, {
    updateNavbarPage(session, "inNavbar", selected = "visualization")
    updateTabsetPanel(session, "X-LDFunctions","X-LD-Plus")
    
    froot <<- currentFile()
    withProgress(message="X-LD-Plus:", value=0, {
      incProgress(1/1, detail = paste0(" collecting information ..."))
      
      nn<-nrow(read.table(paste0(froot, ".fam"), as.is = T, header = F, colClasses = c("character","NULL","NULL","NULL","NULL","NULL")))
      mm<-nrow(read.table(paste0(froot,'.bim'), as.is = T, header=F, colClasses = c("character","NULL","NULL","NULL","NULL","NULL")))
    })
    
    withProgress(message="X-LD-Plus:", value=0, {
      time1 = proc.time()
      n = 4
      B=input$times
      # prepare header and individual ID for plink input
      system(paste0("echo '#FID\tIID\t", paste0("zb", 1:B, collapse = '\t'), "' >",froot,".head.tmp"))
      system(paste0("awk 'BEGIN{OFS=\"\t\"}{print $1,$2}' ", froot,".fam > ",froot,".id.tmp"))
      # random matrix: zb(n*B)
      zb = matrix(NA, nn, B)
      zb = apply(zb, 2, assign.random)
      
      # prepare plink --linear fake phenotype
      write.table(format(zb, digits = 6), paste0(froot,".zb.tmp"), quote = F, col.names = F, row.names = F, sep = '\t')
      system(paste0("paste -d \"\t\" ",paste0(froot,".id.tmp "), paste0(froot,".zb.tmp")," > ",froot,".idzb.tmp")) 
      
      # random matrix (n*(B+2))
      system(paste0("cat ",froot,".head.tmp ",froot,".idzb.tmp > ",froot,".zb.txt"))  
      
      Chr_Me_Matr <- data.frame(matrix(NA,nrow=input$autosome,ncol=input$autosome))
      rownames(Chr_Me_Matr)[1:input$autosome] <- c(paste0("chr",seq(1,input$autosome,1)))
      colnames(Chr_Me_Matr)[1:input$autosome] <- c(paste0("chr",seq(1,input$autosome,1)))
      # chr marker
      Chr_Mark_Matr <- data.frame(matrix(NA,nrow=input$autosome,ncol=input$autosome))
      rownames(Chr_Mark_Matr)[1:input$autosome] <- c(paste0("chr",seq(1,input$autosome,1)))
      colnames(Chr_Mark_Matr)[1:input$autosome] <- c(paste0("chr",seq(1,input$autosome,1)))
      # variance
      Chr_Lb_Var_Matr <- data.frame(matrix(NA,nrow=input$autosome,ncol=input$autosome))
      rownames(Chr_Lb_Var_Matr)[1:input$autosome] <- c(paste0("chr",seq(1,input$autosome,1)))
      colnames(Chr_Lb_Var_Matr)[1:input$autosome] <- c(paste0("chr",seq(1,input$autosome,1)))
      
      incProgress(1/n, detail = paste0(" calculate chromosome level LD ..."))
      sc=ifelse(input$bred == 'inbred', 2, 1)
      
      for(i in 1:input$autosome){
        Chr_Mark_Num_cmd = paste0("cat ",froot,".bim | grep -w '^",i,"' | wc -l")
        Chr_Mark_Num = system(Chr_Mark_Num_cmd,intern = TRUE)
        Chr_Mark_Num <- as.numeric(Chr_Mark_Num)
        # Determine whether chromosomes exist
        if(Chr_Mark_Num==0){
          Chr_Mark_Matr[i,i] <- NA
          next
        }else{
          Chr_Mark_Matr[i,i] <- Chr_Mark_Num
          incProgress(2/n, detail = paste0(" calculate chromosome level LD for chromosome ",i ," ..."))
          # When both X and Z are normalized, X^T*Z=(n-1)Beta. When x is not normalized, X^T*Z=(n-1)*t/sqrt(n-1+t^2)=t*sqrt(n-1) [large sample] 
          system(paste0(plink2," --bfile ", froot," --chr ",i," --chr-set 90 --allow-extra-chr --allow-no-sex --no-psam-pheno --glm allow-no-covars --pheno ",froot,".zb.txt"," --threads 10 --memory 102400 --out ",froot,".chr",i))
          # construct scoring file
          cmd = paste0("awk 'BEGIN{OFS=\"\\t\"}(NR>1){print $3,$6,$11*sqrt($8)}' ",froot,".chr",i, ".zb1.glm.linear > ", froot,".xzb.1.tmp")
          system(cmd)
          cmd = paste0("paste ", paste0("<(awk 'BEGIN{OFS=\"\\t\"}(NR>1){print $11*sqrt($8)}' ", froot,".chr",i, ".zb", 2:B, ".glm.linear) ", collapse = ""), " > ", froot,".xzb.2.tmp", collapse = "")
          write("#!/bin/bash\n", paste0(froot,".scoring.construct.bash"))
          write(cmd, paste0(froot,".scoring.construct.bash"), append = T)
          system(paste0("bash ",froot,".scoring.construct.bash"))
          cmd = paste0("paste ",froot,".xzb.1.tmp ",froot, ".xzb.2.tmp > ",froot, ".xzb.tmp")
          system(cmd)
          
          # allele frequency
          system(paste0(plink2," --bfile ",froot, " --chr-set ",input$autosome, " --chr ",i," --freq --out ",froot,".chr",i))
          
          # plink X*X^T*Z
          system(paste0(plink2," --bfile ",froot, " --chr-set ",input$autosome, " --chr ",i," --no-psam-pheno --read-freq ", froot,".chr",i,".afreq --score ",froot,".xzb.tmp"," 1 2 variance-standardize --score-col-nums 3-", 2+B, " --out ", froot,".chr",i))
          
          # remove linear regression results
          system(paste0("rm -rf ",froot,".chr",i,".afreq ",froot,".chr",i,".zb*"))
          # read in xxz
          xxz = data.frame(fread(paste0(froot,".chr",i, ".sscore"), header = T))
          xxz = as.matrix(xxz[,3]*xxz[,c(5:ncol(xxz))])
          SS = colSums(xxz^2, na.rm = T)
          
          # trace(K2) 
          trK2 = sum(SS)/(Chr_Mark_Matr[i,i]^2)/B/as.numeric(sc)
          Chr_Me_Matr[i,i] <- nn^2/(trK2-nn) # me
          Chr_Lb_Var_Matr[i,i] <- (2/B)*(nn+(3*nn^3-3*nn^2+2*nn)/((nn-1)^3)+6*nn^2/Chr_Me_Matr[i,i]+(4*nn^2+4*nn)/(Chr_Me_Matr[i,i]*(nn-1))+(2*nn^3+2*nn^2-nn)/(Chr_Me_Matr[i,i]^2))
        }
        
      }
      time2 = proc.time()
      time = (time2-time1)[3][[1]]
      print(paste0(froot,' takes ',time,' seconds to finish the decomposition of me.'))
      
      for(i in 1:input$autosome){
        if(is.na(Chr_Mark_Matr[i,i])){
          next
        }else{
          SNP1=as.numeric(Chr_Mark_Matr[i,i])
          # score value for chromosome i
          xxz1 = data.frame(fread(paste0(froot,".chr",i, ".sscore"), header = T))
          xxz1 = as.matrix(xxz1[,3]*xxz1[,c(5:ncol(xxz1))])
          for(j in 1:input$autosome){
            if(is.na(Chr_Mark_Matr[j,j])){
              next
            }else{
              if(i<j){
                SNP2=as.numeric(Chr_Mark_Matr[j,j])
                Chr_Mark_Matr[i,j]=SNP1+SNP2
                # score value for chromosome j 
                xxz2 = data.frame(fread(paste0(froot,".chr",j, ".sscore"), header = T))
                xxz2 = as.matrix(xxz2[,3]*xxz2[,c(5:ncol(xxz2))])
                xxz1_2 = xxz1 + xxz2
                SS = colSums(xxz1_2^2, na.rm = T)
                trK2 = sum(SS)/(Chr_Mark_Matr[i,j]^2)/B/as.numeric(sc)
                Chr_Me_Matr[i,j] <- nn^2/(trK2-nn) # me
                Chr_Lb_Var_Matr[i,j] <- (2/B)*(nn+(3*nn^3-3*nn^2+2*nn)/((nn-1)^3)+6*nn^2/Chr_Me_Matr[i,j]+(4*nn^2+4*nn)/(Chr_Me_Matr[i,j]*(nn-1))+(2*nn^3+2*nn^2-nn)/(Chr_Me_Matr[i,j]^2))
              }
            }
          }
          
        }
      }
      system(paste0("rm -rf ",froot,".chr*"))
      # Fill lower triangle
      Chr_Me_Matr[lower.tri(Chr_Me_Matr)] <- t(Chr_Me_Matr)[lower.tri(Chr_Me_Matr)]
      Chr_Mark_Matr[lower.tri(Chr_Mark_Matr)] <- t(Chr_Mark_Matr)[lower.tri(Chr_Mark_Matr)]
      # Remove empty chromosome
      Chr_Me_Matr <- Chr_Me_Matr[apply(Chr_Me_Matr,1,function(y) any(!is.na(y))),]
      Chr_Me_Matr <- Chr_Me_Matr[,apply(Chr_Me_Matr,2,function(y) any(!is.na(y)))]
      
      Chr_Mark_Matr <- Chr_Mark_Matr[apply(Chr_Mark_Matr,1,function(y) any(!is.na(y))),]
      Chr_Mark_Matr <- Chr_Mark_Matr[,apply(Chr_Mark_Matr,2,function(y) any(!is.na(y)))]
      
      Chr_Lb_Var_Matr <- Chr_Lb_Var_Matr[apply(Chr_Lb_Var_Matr,1,function(y) any(!is.na(y))),]
      Chr_Lb_Var_Matr <- Chr_Lb_Var_Matr[,apply(Chr_Lb_Var_Matr,2,function(y) any(!is.na(y)))]
      
      LD <- as.data.frame(matrix(NA,nrow=nrow(Chr_Me_Matr),ncol=nrow(Chr_Me_Matr)))
      colnames(LD) <- rownames(Chr_Me_Matr)
      rownames(LD) <- rownames(Chr_Me_Matr)
      for(i in 1:nrow(LD)){
        for(j in 1:ncol(LD)){
          # intra-chromosomal LD
          if(i==j){
            LD[i,i] <- (Chr_Mark_Matr[i,i]^2/Chr_Me_Matr[i,i]-Chr_Mark_Matr[i,i])/(Chr_Mark_Matr[i,i]*(Chr_Mark_Matr[i,i]-1))
          }else{
            # inter-chromosomal LD
            LD[i,j] <- (Chr_Mark_Matr[i,j]^2/Chr_Me_Matr[i,j]-Chr_Mark_Matr[i,i]^2/Chr_Me_Matr[i,i]-Chr_Mark_Matr[j,j]^2/Chr_Me_Matr[j,j])/(2*Chr_Mark_Matr[i,i]*Chr_Mark_Matr[j,j])
          }
        }
      }
      
      LD <- as.matrix(LD)
      LD[LD < 0] <- 1e-300
      LD_Final <- adjustdata(LD)
      colnames(LD_Final)[1] <- ""
      Output3="X_LD_Plus.txt"
      write.table(LD_Final,file=Output3,quote = FALSE,sep="\t",row.names = FALSE)
      #write.table(LD_Final,file=paste0(froot,".X_LD.txt"),quote = FALSE,sep="\t",row.names = FALSE)
      # LD scale calculate
      LD_Scale <- as.data.frame(matrix(NA,nrow=nrow(Chr_Me_Matr),ncol=nrow(Chr_Me_Matr)))
      colnames(LD_Scale) <- rownames(Chr_Me_Matr)
      rownames(LD_Scale) <- rownames(Chr_Me_Matr)
      for(i in 1:nrow(LD_Scale)){
        for(j in 1:nrow(LD_Scale)){
          # within chr
          if(i==j){
            LD_Scale[i,j] <- 1
          }else{
            LD_Scale[i,j] <- LD[i,j]/(sqrt(LD[i,i])*sqrt(LD[j,j]))
          }
        }
      }
      
      LD_Scale <- as.matrix(LD_Scale)
      LD_Scale_Final <- adjustdata(LD_Scale)
      colnames(LD_Scale_Final)[1] <- ""
      Output4="X_LD_Plus_Scaled.txt"
      write.table(LD_Scale_Final,file=Output4,quote = FALSE,sep="\t",row.names = FALSE)
      #write.table(LD_Scale_Final,file=paste0(froot,".X_LD_Scaled.txt"),quote = FALSE,sep="\t",row.names = FALSE)
      Log_LD <- -log10(LD)
      Log_LD[lower.tri(Log_LD)] <- NA
      Melt1 <- reshape2::melt(Log_LD, na.rm = TRUE)
      Max=max(Melt1[,3])
      Min=min(Melt1[,3])
      Mid=(Max+Min)/2
      
      LD_Scale[lower.tri(LD_Scale)] <- NA
      Melt2 <- reshape2::melt(LD_Scale, na.rm = TRUE)
    })
    
    withProgress(message="X-LD complete! Visualizing:", value=0, { 
      n=4
      incProgress(1/n, detail = paste0(" LD plot ... "))
      #Output5=paste0(froot,"_X_LD.pdf")
      #Output6=paste0(froot,"_X_LD_Scaled.pdf")
      # Log conversion
      # Log_LD <- -log10(LD)
      # Log_LD[lower.tri(Log_LD)] <- NA
      # Melt <- melt(Log_LD, na.rm = TRUE)
      # Max=max(Melt[,3])
      # Min=min(Melt[,3])
      # Mid=(Max+Min)/2
      
      output$me <- renderPlot({
        ggplot(data = Melt1, aes(Var2, Var1, fill = value))+
          geom_tile(color = "white")+
          scale_fill_gradient2(low = "#FF0000", high = "#FFFFFF", mid = "#FF9E81",space = "Lab",
                               midpoint = Mid, limit = c(Min,Max),name=expression(paste(-log[10],"LD"))) +
          theme_minimal()+
          scale_y_discrete(position = "right") +
          theme(
            text=element_text(family="serif"),
            axis.title.x = element_blank(),
            axis.text.x = element_text(angle = 90,family="serif"),
            axis.title.y = element_blank(),
            axis.text.y  = element_text(family="serif"),
            panel.grid.major = element_blank(),
            panel.border = element_blank(),
            panel.background = element_blank(),
            axis.ticks = element_blank(),
            legend.justification = c(1, 0),
            legend.position = c(0.6, 0.7),
            legend.direction = "horizontal")+
          guides(fill = guide_colorbar(barwidth = 7, barheight = 1,
                                       title.position = "top", title.hjust = 0.5)) +
          coord_fixed()
       
      })
      P1 <- ggplot(data = Melt1, aes(Var2, Var1, fill = value))+
        geom_tile(color = "white")+
        scale_fill_gradient2(low = "#FF0000", high = "#FFFFFF", mid = "#FF9E81",space = "Lab",
                             midpoint = Mid, limit = c(Min,Max),name=expression(paste(-log[10],"LD"))) +
        theme_minimal()+
        scale_y_discrete(position = "right") +
        theme(
          text=element_text(family="serif"),
          axis.title.x = element_blank(),
          axis.text.x = element_text(angle = 90,family="serif"),
          axis.title.y = element_blank(),
          axis.text.y  = element_text(family="serif"),
          panel.grid.major = element_blank(),
          panel.border = element_blank(),
          panel.background = element_blank(),
          axis.ticks = element_blank(),
          legend.justification = c(1, 0),
          legend.position = c(0.6, 0.7),
          legend.direction = "horizontal")+
        guides(fill = guide_colorbar(barwidth = 7, barheight = 1,
                                     title.position = "top", title.hjust = 0.5)) +
        coord_fixed()
      ggsave("X_LD_Plus.pdf",P1,width=10,height=10)
      
      incProgress(2/n, detail = paste0(" LD (scaled) plot ... "))
      #LD_Scale <- data.frame(read.table(froot,".X_LD_Scaled.txt"))
      # LD_Scale[lower.tri(LD_Scale)] <- NA
      # Melt <- melt(LD_Scale, na.rm = TRUE)
      
      output$me_scale <- renderPlot({
        ggplot(data = Melt2, aes(Var2, Var1, fill = value))+
          geom_tile(color = "white")+
          scale_fill_gradient2(low = "#FFFFFF", high = "#FF0000",mid = "#FF9E81",
                               midpoint = 0.5, limit = c(0,1), space = "Lab",
                               name="LD (scaled)") +
          theme_minimal()+
          scale_y_discrete(position = "right") +
          theme(
            text=element_text(family="serif"),
            axis.title.x = element_blank(),
            axis.text.x = element_text(angle = 90,family="serif"),
            axis.title.y = element_blank(),
            axis.text.y  = element_text(family="serif"),
            panel.grid.major = element_blank(),
            panel.border = element_blank(),
            panel.background = element_blank(),
            axis.ticks = element_blank(),
            legend.justification = c(1, 0),
            legend.position = c(0.6, 0.7),
            legend.direction = "horizontal")+
          guides(fill = guide_colorbar(barwidth = 7, barheight = 1,
                                       title.position = "top", title.hjust = 0.5)) +
          coord_fixed()
        
      })
      P2 <- ggplot(data = Melt2, aes(Var2, Var1, fill = value))+
        geom_tile(color = "white")+
        scale_fill_gradient2(low = "#FFFFFF", high = "#FF0000",mid = "#FF9E81",
                             midpoint = 0.5, limit = c(0,1), space = "Lab",
                             name="LD (scaled)") +
        theme_minimal()+
        scale_y_discrete(position = "right") +
        theme(
          text=element_text(family="serif"),
          axis.title.x = element_blank(),
          axis.text.x = element_text(angle = 90,family="serif"),
          axis.title.y = element_blank(),
          axis.text.y  = element_text(family="serif"),
          panel.grid.major = element_blank(),
          panel.border = element_blank(),
          panel.background = element_blank(),
          axis.ticks = element_blank(),
          legend.justification = c(1, 0),
          legend.position = c(0.6, 0.7),
          legend.direction = "horizontal")+
        guides(fill = guide_colorbar(barwidth = 7, barheight = 1,
                                     title.position = "top", title.hjust = 0.5)) +
        coord_fixed()
      ggsave("X_LD_Plus_Scaled.pdf",P2,width=10,height=10)
  
      output$figure <- downloadHandler( 
        filename = function(){
          paste0('X-LD-Plus_Fig.zip')
        },
        
        content = function(file) {
          froot = currentFile()
          files = NULL
          fname1=paste0("X_LD_Plus",".pdf")
          fname2=paste0("X_LD_Plus_Scaled",".pdf")
          fs <- c(fname1,fname2)
          zip(zipfile = file, files = fs)
          }
        )
  
      output$LD <- downloadHandler(          
        filename = function(){
          paste0("X-LD-Plus_Table.zip")
        },
        content = function(file) {
          froot = currentFile()
          files = NULL
          fname1=paste0("X_LD_Plus",".txt")
          fname2=paste0("X_LD_Plus_Scaled",".txt")
          fs <- c(fname1,fname2)
          zip(zipfile = file, files = fs)
        }
      )                  
  })
})
}
#})
# Run the application
shinyApp(ui = ui, server = server)
