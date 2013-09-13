/*
 * Copyright (c) 2013 Red Hat Inc.
 * 
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2 of the License, or (at your
 * option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 *
 * Lookup up the metrics named on stdin and generate pmDesc descriptors.
 * Mark Goodwin <mgoodwin@redhat.com> May 2013.
 */

#include <pcp/pmapi.h>
#include <pcp/impl.h>
#include <pcp/pmda.h>

static char *semStr[] = { "0", "PM_SEM_COUNTER", "2", "PM_SEM_INSTANT", "PM_SEM_DISCRETE" };

static char *
indomStr(int indom)
{
    static char buf[16];
    
    if (indom == PM_INDOM_NULL)
    	strcpy(buf, "PM_INDOM_NULL");
    else
        sprintf(buf, "0x%04x", indom);

    return buf;
}

int
main(int argc, char *argv[])
{
    int ctx;
    int sts;
    char buf[1024];
    char *name = buf;
    char *p;
    pmID pmid;
    pmDesc desc;

    ctx = pmNewContext(PM_CONTEXT_HOST, "local:");
    if (ctx < 0) {
    	fprintf(stderr, "Error: pmNewContext %s\n", pmErrStr(ctx));
	exit(1);
    }

    printf("/* This file is automatically generated .. do not edit! */\n");
    printf("#include \"metrics.h\"\n\n");

    printf("metric_t metrics[] = {\n");
    while (fgets(buf, sizeof(buf), stdin)) {
	if ((p = strrchr(buf, '\n')) != NULL)
	    *p = '\0';

	if ((sts = pmLookupName(1, &name, &pmid)) < 0) {
	    fprintf(stderr, "Error: pmLookupName \"%s\": %s\n", name, pmErrStr(sts));
	    exit(1);
	}

	if ((sts = pmLookupDesc(pmid, &desc)) < 0) {
	    fprintf(stderr, "Error: pmLookupDesc \"%s\": %s\n", name, pmErrStr(sts));
	    exit(1);
	}

	printf("    /* %-8s */ { \"%s\", { 0x%04x, PM_TYPE_%s, %s, %s,\n"
	       "                  { .dimSpace=%d, .dimTime=%d, .dimCount=%d, "
	       ".scaleSpace=%d, .scaleTime=%d, .scaleCount=%d } } },\n",
	    pmIDStr(desc.pmid), name, desc.pmid, pmTypeStr(desc.type),
	    indomStr(desc.indom), semStr[desc.sem], desc.units.dimSpace,
	    desc.units.dimTime, desc.units.dimCount, desc.units.scaleSpace,
	    desc.units.scaleTime, desc.units.scaleCount);
    }

    printf("    { NULL }\n};\n");
    exit(0);
}