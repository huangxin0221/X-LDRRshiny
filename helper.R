## pre-defined function
assign.random <- function(x){
  x = scale(rnorm(length(x), 0, 1))
  x
}

adjustdata <- function(data) {
  data<-cbind(rownames(data),data)
}

