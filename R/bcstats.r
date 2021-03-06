#' Comparing "back checks" in R (a clone of Stata's bcstats)
#' 
#' @param surveydata The survey data
#' @param bcdata The back check data
#' @param id The unique ID
#' @param enumerator Display enumerators with high error rates and variables
#' with high error rates for those enumerators
#' @param enumteam Display the overall error rates of all enumerator teams
#' @param t1vars The list of "type 1" variables. See details.
#' @param t2vars The list of "type 2" variables. See details.
#' @param t3vars The list of "type 3" variables. See details.
#' @param ttest Run paired two-sample mean-comparison tests for varlist in the
#' back check and survey data using ttest
#' @param level Set confidence level for ttest; default is 0.95
#' @param signrank Run Wilcoxon matched-pairs signed-ranks tests in the back
#' check and survey data using signrank
#' @param lower Convert all string variables to lower case before comparing
#' @param upper Convert all string variables to upper case before comparing
#' @param nosymbol Replace symbols with spaces in string variables before
#' comparing
#' @param trim Remove leading or trailing blanks and multiple, consecutive
#' internal blanks in string variables before comparing
#' @param okrange Do not count a value in list in the back check data as a
#' difference if it falls within range of the survey data
#' @param nodiff Do not compare back check responses that equal # (for numeric
#' variables) or string (for string variables)
#' @param exclude Specifies that back check responses that equal values in list
#' will not be compared. These responses will not affect error rates and will
#' not appear in the comparisons data set.  Used when the back check data set
#' contains data for multiple back check survey versions. 
#' @return A named list constaining the back check as a data.frame, error rates
#' by groups, and tests for differences
#' @details
#' Variable types:
#' \itemize{
#' \item Type 1 variables are expected to stay constant between the survey and
#' back check, and differences may result in action against the enumerator.
#' \item Type 2 variables may be difficult for enumerators to administer. For
#' instance, they may involve complicated skip patterns or many examples.
#' Differences may indicate the need for further training, but will not result
#' in action against the enumerator.
#' \item Type 3 variables are variables whose stability between the survey and
#' back check is of interest. Differences will not result in action against the
#' enumerator.
#' }
#' @export

bcstats <- function(surveydata,
                    bcdata,
                    id,
                    enumerator  = NA,
                    enumteam    = NA,
                    backchecker = NA,
                    bcteam      = NA,
                    t1vars      = NA,
                    t2vars      = NA,
                    t3vars      = NA,
                    ttest       = NA,
                    level       = 0.95,
                    signrank    = NA,
                    lower       = FALSE,
                    upper       = FALSE,
                    nosymbol    = FALSE,
                    trim        = FALSE,
                    okrange     = NA,
                    nodiff      = NA,
                    exclude     = NA) {

    # Create list that will store all the results
    results  <- list(backcheck    = NA,
                     enum1        = vector("list"),
                     enum2        = vector("list"),
                     enumteam1    = vector("list"),
                     enumteam2    = vector("list"),
                     backchecker1 = vector("list"),
                     backchecker2 = vector("list"),
                     bcteam1      = vector("list"),
                     bcteam2      = vector("list"),
                     ttest        = vector("list"),
                     signrank     = vector("list"))

    # Pre-process data when needed
    surveydata <- .bcstats.pre(pp.data  = surveydata,
                               lower    = lower,
                               upper    = upper,
                               trim     = trim,
                               nosymbol = nosymbol)

    bcdata     <- .bcstats.pre(pp.data  = bcdata,
                               lower    = lower,
                               upper    = upper,
                               trim     = trim,
                               nosymbol = nosymbol)

    pairwise <- merge(melt(surveydata, id = id),
                      melt(bcdata,     id = id),
                      by       = c(id,        "variable"),
                      suffixes = c(".survey", ".backcheck"))

    pairwise$variable <- as.character(pairwise$variable)

    # Categorize error types
    pairwise$type                                <- ""
    pairwise$type[pairwise$variable %in% t1vars] <- "type 1"
    pairwise$type[pairwise$variable %in% t2vars] <- "type 2"
    pairwise$type[pairwise$variable %in% t3vars] <- "type 3"
    pairwise                                     <- pairwise[which(pairwise$type != ""), ]

    # Create a logical value for whether or not the entry contains an error
    pairwise$error <- pairwise$value.survey != pairwise$value.backcheck
    pairwise$error <- !(pairwise$error %in% FALSE)
    pairwise$error[is.na(pairwise$value.survey) & is.na(pairwise$value.backcheck)] <- FALSE

    # No error for variables within okrange
    if (!is.na(okrange)) {
      for (name in names(okrange)) {
        ok.var   <- pairwise[which(pairwise$variable == name), ]
        ok.min   <- okrange[[name]][1]
        ok.max   <- okrange[[name]][2]
        ok.check <- as.numeric(ok.var$value.back_check) >= as.numeric(ok.var$value.survey) - ok.min &&
                    as.numeric(ok.var$value.survey) + ok.max >= as.numeric(ok.var$value.back_check)
        pairwise[which(pairwise$variable == name), ]$error <- ok.check
      }
    }

    # No error for nodiff group
    if (!is.na(nodiff)) {
      for (name in names(nodiff)) {
        pairwise$error[(pairwise$variable == name &
                        pairwise$value.survey %in% nodiff[[name]])] <- FALSE
      }
    }

    # Exclude some cases
    if (!is.na(exclude)) {
      for (name in names(exclude)) {
        pairwise$type[(pairwise$variable == name &
                       pairwise$value.survey %in% exclude[[name]])] <- ""
      }
      pairwise <- pairwise[which(pairwise$type != ""), ]
    }

    # Identifiers
    sid_vars <- c(id, enumerator, enumteam)
    bid_vars <- c(id, backchecker, bcteam)
    sid_vars <- sid_vars[!is.na(sid_vars)]
    bid_vars <- bid_vars[!is.na(bid_vars)]
    id_vars  <- unique(c(sid_vars, bid_vars))

    # Merge back in identifiers
    if (length(sid_vars) > 1) {
      pairwise <- merge(pairwise,
                        surveydata[, sid_vars],
                        all = FALSE,
                        by  = id)
    }
    
    if (length(bid_vars) > 1) {
      pairwise <- merge(pairwise,
                        bcdata[, bid_vars],
                        all = FALSE,
                        by  = id)
    }

    # Restrict the data to cases where there is an error
    backcheck           <- pairwise[which(pairwise$error == TRUE),
                                    c(id_vars,
                                      "type",
                                      "variable",
                                      "value.survey",
                                      "value.backcheck",
                                      "error")]
    rownames(backcheck) <- NULL
    # order_vars          <- c(id_vars, "type", "variable")
    # backcheck           <- backcheck %>% arrange_(.dots = order_vars)
    results$backcheck   <- backcheck[,
                                     c(id_vars,
                                       "type",
                                       "variable",
                                       "value.survey",
                                       "value.backcheck")]

    # Remove type 3 variables from error calculations that follow
    pairwise$error[pairwise$type == "type 3"] <- FALSE

    groups <- list(enum1        = c(enumerator,  is.na(t1vars), "type 1"),
                   enum2        = c(enumerator,  is.na(t2vars), "type 2"),
                   enumteam1    = c(enumteam,    is.na(t1vars), "type 1"),
                   enumteam2    = c(enumteam,    is.na(t2vars), "type 2"),
                   backchecker1 = c(backchecker, is.na(t1vars), "type 1"),
                   backchecker2 = c(backchecker, is.na(t2vars), "type 2"),
                   bcteam1      = c(bcteam,      is.na(t1vars), "type 1"),
                   bcteam2      = c(bcteam,      is.na(t2vars), "type 2"))

    for (name in names(groups)) {
      group.name  <- groups[[name]][1]
      isna.vars   <- as.logical(groups[[name]][2])
      group.error <- groups[[name]][3]

      if (is.na(group.name) | isna.vars) {
        results[[name]] <- NULL
      } else {
        calc.error.by.group     <- .calc.error.by.group(pairwise   = pairwise,
                                                        id         = id,
                                                        group.id   = group.name,
                                                        error.type = group.error)
        results[[name]]$summary <- calc.error.by.group$summary
        results[[name]]$each    <- calc.error.by.group$each        
      }
    }

    # Run the t-tests (if none specified remove from results)
    if (is.na(ttest)) {
      results[["ttest"]] <- NULL
    } else {
        for (var in ttest) {
            pairwise.var         <- pairwise[which(pairwise$variable == var),  ]
            results$ttest[[var]] <- t.test(as.numeric(pairwise.var$value.survey),
                                           as.numeric(pairwise.var$value.backcheck),
                                           paired     = TRUE,
                                           conf.level = level)    
        }
    }

    # Run the Wilcoxon signed rank test (if none specified remove from results)
    if (is.na(signrank)) {
      results[["signrank"]] <- NULL
    } else {
        for (var in signrank) {
            pairwise.var            <- pairwise[which(pairwise$variable == var),  ]
            results$signrank[[var]] <- wilcox.test(as.numeric(pairwise.var$value.survey),
                                                   as.numeric(pairwise.var$value.backcheck),
                                                   paired = TRUE)    
        }
    }

    # Return the results
    return(results)
}

# Helper function that calculates error rates by group id (e.g., enumerator, team)
.calc.error.by.group <- function(pairwise,
                                 id,
                                 group.id,
                                 error.type) {

      results.by.group <- list(summary = NA,
                               each    = NA)

      pairwise  <- pairwise[which(pairwise$type == error.type), ]

      if (is.na(group.id)) {
        summary <- aggregate(pairwise[ , c("error")],
                             by  = list(pairwise$variable),
                             FUN = function(x) c(error.rate  = mean(x),
                                                 differences = sum(x), 
                                                 total       = length(x)))
      } else {
        summary <- aggregate(pairwise[ , c("error")],
                             by  = list(pairwise[[group.id]]),
                             FUN = function(x) c(error.rate  = mean(x),
                                                 differences = sum(x), 
                                                 total       = length(x)))
        each    <- aggregate(pairwise[ , c("error")],
                             by  = list(pairwise[[group.id]],
                                        pairwise$variable),
                             FUN = function(x) c(error.rate  = mean(x),
                                                 differences = sum(x), 
                                                 total       = length(x)))
      }
      # Name the columns
      summary <- as.data.frame(as.list(summary))
      names(summary) <- c(group.id, "error.rate", "differences", "total")

      if (!is.na(group.id)) {
        each        <- as.data.frame(as.list(each))
        names(each) <- c(group.id, "variable", "error.rate", "differences", "total")
      }

      # Export results
      results.by.group$summary <- summary
      results.by.group$each    <- each
      return(results.by.group)
}

# Functions that pre-proccesses the data
.bcstats.pre <- function(pp.data, lower, upper, trim, nosymbol) {
    if (lower & upper) {
      stop("Cannot have both lower and upper case at the same time")
    } else if (lower) {
      pp.data <- data.frame(lapply(pp.data, .lower.ifchar), stringsAsFactors = FALSE)
    } else if (upper) {
      pp.data <- data.frame(lapply(pp.data, .upper.ifchar), stringsAsFactors = FALSE)
    }

    if (trim) {
      pp.data <- data.frame(lapply(pp.data, .trim.ifchar), stringsAsFactors = FALSE)
    }

    if (nosymbol) {
      pp.data <- data.frame(lapply(pp.data, .nosymbols.ifchar), stringsAsFactors = FALSE)
    }

    return(pp.data)
}

# Change to upper only if vector is character
.upper.ifchar <- function(x) {
  if (class(x) == "character") {
    toupper(x)
  } else {
    x
  }
}

# Change to lower only if vector is character
.lower.ifchar <- function(x) {
  if (class(x) == "character") {
    tolower(x)
  } else {
    x
  }
}

# Trim only if vector is character
.trim.ifchar <- function(x) {
  if (class(x) == "character") {
    trimws(x)
  } else {
    x
  }
}

# Remove symbols only if vector is character
.nosymbols.ifchar <- function(x) {
  if (class(x) == "character") {
    gsub("[[:punct:]]", "", x)
  } else {
    x
  }
}

