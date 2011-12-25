/*
 * Copyright (c) 1995-2003 Silicon Graphics, Inc.  All Rights Reserved.
 * 
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 * 
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 */

#include "pmapi.h"
#include "impl.h"
#include <ctype.h>

static __pmLogPort *logport;
					/* array of all known pmlogger ports */
static int	nlogports;		/* no. of elements used in logports array */
static int	szlogport;		/* size of logport array */

/* Make sure the logports array is large enough to hold newsize entries.  Free
 * any currently allocated names and zero the first newsize entries.
 */
static int
resize_logports(int newsize)
{
    int	i;
    int	need;

    if (nlogports) {
	for (i = 0; i < nlogports; i++) {
	    if (logport[i].pmcd_host != NULL)
		free(logport[i].pmcd_host);
	    if (logport[i].archive != NULL)
		free(logport[i].archive);
	    if (logport[i].name != NULL)
		free(logport[i].name);
	}
	memset(logport, 0, nlogports * sizeof(__pmLogPort));
    }
    nlogports = 0;
    if (szlogport >= newsize)
	return 0;
    free(logport);
    need = newsize * (int)sizeof(__pmLogPort);
    if ((logport = (__pmLogPort *)malloc(need)) == NULL) {
	szlogport = 0;
	return -1;
    }
    memset(logport, 0, need);
    szlogport = newsize;
    return 0;
}

/* Used by scandir to determine which files are pmlogger port files.  The valid
 * files are numbers (pids) or PM_LOG_PRIMARY_LINK for the primary logger.
 */
static int
is_portfile(const_dirent *dep)
{
    char	*endp;
    pid_t	pid;

    pid = (pid_t)strtol(dep->d_name, &endp, 10);
    if (pid > (pid_t)1)
	return __pmProcessExists(pid);
    return strcmp(dep->d_name, "primary") == 0;
}

/* The following function is used for selecting particular port files rather
 * than all valid files.  snprintf the pid of the pmlogger process or the
 * special constant PM_LOG_PRIMARY_LINK into the match array first.
 */
#define PROCFS_ENTRY_SIZE 40	/* encompass any size of entry for pid */
static char match[PROCFS_ENTRY_SIZE];

static int
is_match(const_dirent *dep)
{
    return strcmp(match, dep->d_name) == 0;
}

/* Return (in result) a list of active pmlogger ports on the local machine.
 * The return value of the function is the number of elements in the array.
 * The caller must NOT free any part of the result stucture, it's storage is
 * managed here.  Subsequent calls will overwrite the data so the caller should
 * copy it if persistence is required.
 */
int
__pmLogFindLocalPorts(int pid, __pmLogPort **result)
{
    static char		dir[MAXPATHLEN];
    static int		lendir;
    int			i, j, n;
    int			nf;		/* number of port files found */
    struct dirent	**files = NULL;	/* array of port file dirents */
    char		*p;
    int			len;
    static char		*namebuf = NULL;
					/* for building file names */
    static int		sznamebuf = 0;	/* current size of namebuf */
    int			(*scanfn)(const_dirent *dep);
    FILE		*pfile;
    char		buf[MAXPATHLEN];

    if (result == NULL)
	return -EINVAL;

    if (lendir == 0)
	lendir = snprintf(dir, sizeof(dir), "%s%cpmlogger",
		pmGetConfig("PCP_TMP_DIR"), __pmPathSeparator());

    /* Set up the appropriate function to select files from the control port
     * directory.  Anticipate that this will usually be an exact match for
     * the primary logger control port.
     */
    scanfn = is_match;
    switch (pid) {
	case PM_LOG_PRIMARY_PID:	/* primary logger control (single) */
	    strcpy(match, "primary");
	    break;

	case PM_LOG_ALL_PIDS:		/* find all ports */
	    scanfn = is_portfile;
	    break;

	default:			/* a specific pid (single) */
	    if (!__pmProcessExists((pid_t)pid)) {
#ifdef PCP_DEBUG
		if (pmDebug & DBG_TRACE_LOG) {
		    fprintf(stderr, "__pmLogFindLocalPorts() -> 0, "
				"pid(%d) doesn't exist\n", pid);
		}
#endif
		*result = NULL;
		return 0;
	    }
	    snprintf(match, sizeof(match), "%d", pid);
	    break;
    }

    nf = scandir(dir, &files, scanfn, alphasort);
    if (nf == -1 && oserror() == ENOENT)
	nf = 0;
    else if (nf == -1) {
	pmprintf("__pmLogFindLocalPorts: scandir: %s\n", osstrerror());
	pmflush();
	return -oserror();
    }
    if (resize_logports(nf) < 0) {
	for (i=0; i < nf; i++)
	    free(files[i]);
	free(files);
	return -oserror();
    }
    if (nf == 0) {
#ifdef PCP_DEBUG
	if (pmDebug & DBG_TRACE_LOG) {
	    fprintf(stderr, "__pmLogFindLocalPorts() -> 0, "
			"num files = 0\n");
	}
#endif
	*result = NULL;
	free(files);
	return 0;
    }

    /* make a buffer for the longest complete pathname found */
    len = (int)strlen(files[0]->d_name);
    for (i = 1; i < nf; i++)
	if ((j = (int)strlen(files[i]->d_name)) > len)
	    len = j;
    /* +1 for trailing path separator, +1 for null termination */
    len += lendir + 2;
    if (len > sznamebuf) {
	if (namebuf != NULL)
	    free(namebuf);
	if ((namebuf = (char *)malloc(len)) == NULL) {
	    __pmNoMem("__pmLogFindLocalPorts.namebuf", len, PM_RECOV_ERR);
	    for (i=0; i < nf; i++)
		free(files[i]);
	    free(files);
	    return -oserror();
	}
	sznamebuf = len;
    }

    /* namebuf is the complete pathname, p points to the trailing filename
     * within namebuf.
     */
    strcpy(namebuf, dir);
    p = namebuf + lendir;
    *p++ = __pmPathSeparator();

    /* open the file, try to read the port number and add the port to the
     * logport array if successful.
     */
    for (i = 0; i < nf; i++) {
	char		*fname = files[i]->d_name;
	int		err = 0;
	__pmLogPort	*lpp = &logport[nlogports];
	
	strcpy(p, fname);
	if ((pfile = fopen(namebuf, "r")) == NULL) {
	    pmprintf("__pmLogFindLocalPorts: pmlogger port file %s: %s\n",
		    namebuf, osstrerror());
	    free(files[i]);
	    pmflush();
	    continue;
	}
	if (!err && fgets(buf, MAXPATHLEN, pfile) == NULL) {
	    if (feof(pfile)) {
		clearerr(pfile);
		pmprintf("__pmLogFindLocalPorts: pmlogger port file %s empty!\n",
			namebuf);
	    }
	    else
		pmprintf("__pmLogFindLocalPorts: pmlogger port file %s: %s\n",
			namebuf, osstrerror());
	    err = 1;
	}
	else {
	    char	*endp;

	    lpp->port = (int)strtol(buf, &endp, 10);
	    if (*endp != '\n') {
		pmprintf("__pmLogFindLocalPorts: pmlogger port file %s: no port number\n",
			namebuf);
		err = 1;
	    }
	    else {
		lpp->pid = (int)strtol(fname, &endp, 10);
		if (*endp != '\0') {
		    if (strcmp(fname, "primary") == 0)
			lpp->pid = PM_LOG_PRIMARY_PORT;
		    else {
			pmprintf("__pmLogFindLocalPorts: unrecognised pmlogger port file %s\n",
				namebuf);
			err = 1;
		    }
		}
	    }
	}
	if (err) {
	    pmflush();
	    fclose(pfile);
	}
	else {
	    if (fgets(buf, MAXPATHLEN, pfile) == NULL) {
		pmprintf("__pmLogFindLocalPorts: pmlogger port file %s: no PMCD host name\n",
			namebuf);
		pmflush();
	    }
	    else {
		char	*q = strchr(buf, '\n');
		if (q != NULL)
		    *q = '\0';
		lpp->pmcd_host = strdup(buf);
		if (fgets(buf, MAXPATHLEN, pfile) == NULL) {
		    pmprintf("__pmLogFindLocalPorts: pmlogger port file %s: no archive base pathname\n",
			    namebuf);
		    pmflush();
		}
		else {
		    char	*q = strchr(buf, '\n');
		    if (q != NULL)
			*q = '\0';
		    lpp->archive = strdup(buf);
		}
	    }
	    fclose(pfile);
	    if ((lpp->name = strdup(fname)) != NULL)
		nlogports++;
	    else {
		if (lpp->pmcd_host != NULL) {
		    free(lpp->pmcd_host);
		    lpp->pmcd_host = NULL;
		}
		if (lpp->archive != NULL) {
		    free(lpp->archive);
		    lpp->archive = NULL;
		}
		break;
	    }
	}
	free(files[i]);
    }
    
    if (i == nf) {			/* all went well */
	n = nlogports;
	*result = logport;
    }
    else {				/* strdup error on fname, clean up */
	*result = NULL;
	for (j = i; j < nf; j++)
	    free(files[j]);
	n = -oserror();
    }
    free(files);
    return n;
}

/*
 * Return 1 if hostname corresponds to the current host, 0 if not and < 0 for
 * an error.
 */
int
__pmIsLocalhost(const char *hostname)
{
    int sts = 0;

    if (strcasecmp(hostname, "localhost") == 0)
	return 1;
    else {
	char lhost[MAXHOSTNAMELEN+1];
	struct hostent * he;

	if (gethostname(lhost, MAXHOSTNAMELEN) < 0)
	   return -oserror();

        if ((he = gethostbyname(lhost)) != NULL ) {
	    int i;
	    unsigned int * laddrs;
	    for ( i=0; he->h_addr_list[i] != NULL; i++ ) ;

	    laddrs = (unsigned int *)calloc(i, sizeof (unsigned int));
	    if ( laddrs != NULL ) {
		int k;
		for ( k=0; k < i; k++ ) {
		    laddrs[k] = ((struct in_addr *)he->h_addr_list[k])->s_addr;
		}

		if ((he = gethostbyname(hostname)) == NULL)
		    return -EHOSTUNREACH;

		for ( i--; i >= 0; i-- ) {
		    for (k = 0; he->h_addr_list[k] != NULL; k++) {
			struct in_addr *s=(struct in_addr *)he->h_addr_list[k];
			if (s->s_addr == laddrs[i]) {
			    free (laddrs);
			    return (1);
			}
		    }
		}

		free (laddrs);
	    }
	}
    }

    return sts;
}

/* Return (in result) a list of active pmlogger ports on the specified machine.
 * The return value of the function is the number of elements in the array.
 * The caller must NOT free any part of the result stucture, it's storage is
 * managed here.  Subsequent calls will overwrite the data so the caller should
 * copy it if persistence is required.
 */
int
__pmLogFindPort(const char *host, int pid, __pmLogPort **lpp)
{
    int			ctx, oldctx;
    int			sts, numval;
    int			i, j;
    int			findone = pid != PM_LOG_ALL_PIDS;
    int			localcon = 0;	/* > 0 for local connection */
    pmDesc		desc;
    pmResult		*res;
    char		*namelist[] = {"pmcd.pmlogger.port"};
    pmID		pmid;

    *lpp = NULL;		/* pass null back in event of error */
    localcon = __pmIsLocalhost(host);
    if (localcon > 0)
	/* do the work here instead of making PMCD do it */
	return __pmLogFindLocalPorts(pid, lpp);
    else if (localcon < 0)
	return localcon;

    /* note: there may not be a current context */
    oldctx = pmWhichContext();

    if ((ctx = pmNewContext(PM_CONTEXT_HOST, host)) < 0)
	return ctx;
    if ((sts = pmLookupName(1, namelist, &pmid)) < 0)
	goto ctxErr;

    if ((sts = pmLookupDesc(pmid, &desc)) < 0)
	goto ctxErr;
    if ((sts = pmFetch(1, &pmid, &res) < 0))
	goto ctxErr;
    if ((sts = numval = res->vset[0]->numval) < 0)
	goto resErr;
    j = 0;
    if (numval) {
	if (resize_logports(findone ? 1 : numval) < 0) {
	    sts = -oserror();
	    goto resErr;
	}
	/* scan the pmResult, copying matching pid(s) to logport */
	for (i = j = 0; i < numval; i++) {
	    __pmLogPort	*p = &logport[j];
	    pmValue	*vp = &res->vset[0]->vlist[i];

	    if (vp->inst == 1)	/* old vcr instance (pseudo-init) */
		continue;
	    if (findone && vp->inst != pid)
		continue;
	    p->pid = vp->inst;
	    p->port = vp->value.lval;
	    sts = pmNameInDom(desc.indom, p->pid, &p->name);
	    if (sts < 0) {
		p->name = NULL;
		goto resErr;
	    }
	    j++;
	    if (findone)		/* found one, stop searching */
		break;
	}
	*lpp = logport;
    }
    sts = j;			/* the number actually added */

resErr:
    pmFreeResult(res);
ctxErr:
    if (oldctx >= 0)
	pmUseContext(oldctx);
    pmDestroyContext(ctx);
    return sts;
}