/*
 * Copyright (c) 2006 Aconex.  All Rights Reserved.
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
#include "pmtime.h"

static int
pmServerExec(int fd, int livemode)
{
    char portname[32];
    int port, in, out;
    char *argv[] = { "pmtime", NULL, NULL };

    if (livemode)
	argv[1] = "-h";	/* -h for live hosts */
    else
	argv[1] = "-a";	/* -a for archives */

    if (__pmProcessCreate(argv, &in, &out) < (pid_t)0) {
	__pmCloseSocket(fd);
	return -1;
    }

    if (read(in, &portname, sizeof(portname)) < 0)
	port = -1;
    else if (sscanf(portname, "port=%d", &port) != 1) {
	setoserror(EPROTO);
	port = -1;
    }
    close(in);
    close(out);
    if (port == -1)
	__pmCloseSocket(fd);
    return port;
}

static int
pmConnectHandshake(int fd, int port, pmTime *pkt)
{
    struct sockaddr_in myaddr;
    char buffer[4096];
    pmTime *ack;
    int sts;

    /*
     * Connect to pmtime - pmtime guaranteed started by now, due to the
     * port number read(2) earlier, or -p option (so no race there).
     */
    memset(&myaddr, 0, sizeof(myaddr));
    myaddr.sin_family = AF_INET;
    myaddr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    myaddr.sin_port = htons(port);
    if ((sts = connect(fd, (struct sockaddr *)&myaddr, sizeof(myaddr))) < 0) {
	setoserror(neterror());
	goto error;
    }

    /*
     * Write the packet, then wait for an ACK.
     */
    sts = send(fd, (const void *)pkt, pkt->length, 0);
    if (sts < 0) {
	setoserror(neterror());
	goto error;
    } else if (sts != pkt->length) {
	setoserror(EMSGSIZE);
	goto error;
    }
    ack = (pmTime *)buffer;
    sts = recv(fd, buffer, sizeof(buffer), 0);
    if (sts < 0) {
	setoserror(neterror());
	goto error;
    } else if (sts != ack->length) {
	setoserror(EMSGSIZE);
	goto error;
    } else if (ack->command != PM_TCTL_ACK) {
	setoserror(EPROTO);
	goto error;
    } else if (ack->source != pkt->source) {
	setoserror(ENOSYS);
	goto error;
    }
    return 0;

error:
    __pmCloseSocket(fd);
    return -1;
}

int
pmTimeConnect(int port, pmTime *pkt)
{
    int	fd;

    if ((fd = __pmCreateSocket()) < 0)
	return -1;
    if (port < 0) {
	if ((port = pmServerExec(fd, pkt->source != PM_SOURCE_ARCHIVE)) < 0)
	    return -2;
	if (pmConnectHandshake(fd, port, pkt) < 0)
	    return -3;
    } else {		/* attempt to connect to the given port (once) */
	if (pmConnectHandshake(fd, port, pkt) < 0)
	    return -4;
    }
    return fd;
}

int
pmTimeDisconnect(int fd)
{
    if (fd < 0) {
	setoserror(EINVAL);
	return -1;
    }
    __pmCloseSocket(fd);
    return 0;
}

int
pmTimeSendAck(int fd, struct timeval *tv)
{
    pmTime data;
    int sts;

    memset(&data, 0, sizeof(data));
    data.magic = PMTIME_MAGIC;
    data.length = sizeof(data);
    data.command = PM_TCTL_ACK;
    data.position = *tv;
    sts = send(fd, (const void *)&data, sizeof(data), 0);
    if (sts < 0)
	setoserror(neterror());
    return sts;
}

int
pmTimeShowDialog(int fd, int show)
{
    pmTime data;
    int sts;

    memset(&data, 0, sizeof(data));
    data.magic = PMTIME_MAGIC;
    data.length = sizeof(data);
    data.command = show ? PM_TCTL_GUISHOW : PM_TCTL_GUIHIDE;
    sts = send(fd, (const void *)&data, sizeof(data), 0);
    if (sts >= 0 && sts != sizeof(data)) {
	setoserror(EMSGSIZE);
	sts = -1;
    } else if (sts < 0)
	setoserror(neterror());
    return sts;
}

int
pmTimeRecv(int fd, pmTime **datap)
{
    pmTime *k = *datap;
    int sts, remains;

    memset(k, 0, sizeof(pmTime));
    sts = recv(fd, (void *)k, sizeof(pmTime), 0);
    if (sts >= 0 && sts != sizeof(pmTime)) {
	setoserror(EMSGSIZE);
	sts = -1;
    } else if (sts < 0) {
	setoserror(neterror());
    } else if (k->length > sizeof(pmTime)) {	/* double dipping */
	remains = k->length - sizeof(pmTime);
	*datap = k = realloc(k, k->length);
	sts = recv(fd, (char *)k + sizeof(pmTime), remains, 0);
	if (sts >= 0 && sts != remains) {
	    setoserror(E2BIG);
	    sts = -1;
	} else if (sts < 0) {
	    setoserror(neterror());
	}
    }
    if (sts < 0)
	return sts;
    return k->command;
}