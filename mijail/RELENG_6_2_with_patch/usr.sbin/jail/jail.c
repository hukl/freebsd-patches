/*
 * ----------------------------------------------------------------------------
 * "THE BEER-WARE LICENSE" (Revision 42):
 * <phk@FreeBSD.ORG> wrote this file.  As long as you retain this notice you
 * can do whatever you want with this stuff. If we meet some day, and you think
 * this stuff is worth it, you can buy me a beer in return.   Poul-Henning Kamp
 * ----------------------------------------------------------------------------
 */

#include <sys/cdefs.h>
__FBSDID("$FreeBSD: src/usr.sbin/jail/jail.c,v 1.20.2.3 2006/05/26 10:30:59 matteo Exp $");

#include <sys/param.h>
#include <sys/jail.h>
#include <sys/sysctl.h>

#include <netinet/in.h>
#include <arpa/inet.h>

#include <err.h>
#include <errno.h>
#include <grp.h>
#include <login_cap.h>
#include <paths.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void	usage(void);
extern char	**environ;

#define GET_USER_INFO do {						\
	pwd = getpwnam(username);					\
	if (pwd == NULL) {						\
		if (errno)						\
			err(1, "getpwnam: %s", username);		\
		else							\
			errx(1, "%s: no such user", username);		\
	}								\
	lcap = login_getpwclass(pwd);					\
	if (lcap == NULL)						\
		err(1, "getpwclass: %s", username);			\
	ngroups = NGROUPS;						\
	if (getgrouplist(username, pwd->pw_gid, groups, &ngroups) != 0)	\
		err(1, "getgrouplist: %s", username);			\
} while (0)

int
main(int argc, char **argv)
{
	login_cap_t *lcap = NULL;
	struct jail j;
	struct passwd *pwd = NULL;
	struct in_addr in;
	gid_t groups[NGROUPS];
	int ch, i, iflag, Jflag, lflag, ngroups, securelevel, uflag, Uflag;
	char path[PATH_MAX], *ep, *username, *ip, *JidFile;
	static char *cleanenv;
	const char *shell, *p = NULL;
	long ltmp;
	FILE *fp;

	iflag = Jflag = lflag = uflag = Uflag = 0;
	securelevel = -1;
	username = JidFile = cleanenv = NULL;
	fp = NULL;

	while ((ch = getopt(argc, argv, "ils:u:U:J:")) != -1) {
		switch (ch) {
		case 'i':
			iflag = 1;
			break;
		case 'J':
			JidFile = optarg;
			Jflag = 1;
			break;
		case 's':
			ltmp = strtol(optarg, &ep, 0);
			if (*ep || ep == optarg || ltmp > INT_MAX || !ltmp)
				errx(1, "invalid securelevel: `%s'", optarg);
			securelevel = ltmp;
			break;
		case 'u':
			username = optarg;
			uflag = 1;
			break;
		case 'U':
			username = optarg;
			Uflag = 1;
			break;
		case 'l':
			lflag = 1;
			break;
		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc < 4)
		usage();
	if (uflag && Uflag)
		usage();
	if (lflag && username == NULL)
		usage();
	if (uflag)
		GET_USER_INFO;
	if (realpath(argv[0], path) == NULL)
		err(1, "realpath: %s", argv[0]);
	if (chdir(path) != 0)
		err(1, "chdir: %s", path);
	memset(&j, 0, sizeof(j));
	j.version = 1;
	j.path = path;
	j.hostname = argv[1];

    for (i = 1, ip = argv[2]; *ip; ip++) {
            if (*ip == ',')
                    i++;
    }
    if ((j.ips = (u_int32_t *)malloc(sizeof(u_int32_t) * i)) == NULL)
            errx(1, "malloc()");
    for (i = 0, ip = strtok(argv[2], ","); ip;
        i++, ip = strtok(NULL, ",")) {
            if (inet_aton(ip, &in) == 0) {
                    free(j.ips);
                    errx(1, "Couldn't make sense of ip-number: %s", ip);
            }
            j.ips[i] = ntohl(in.s_addr);
    }
    j.nips = i;

	if (Jflag) {
		fp = fopen(JidFile, "w");
		if (fp == NULL)
			errx(1, "Could not create JidFile: %s", JidFile);
	}
	i = jail(&j);
	if (i == -1)
		err(1, "jail");
	if (iflag) {
		printf("%d\n", i);
		fflush(stdout);
	}
	if (Jflag) {
		if (fp != NULL) {
			fprintf(fp, "%d\t%s\t%s\t%s\t%s\n",
			    i, j.path, j.hostname, argv[2], argv[3]);
			(void)fclose(fp);
		} else {
			errx(1, "Could not write JidFile: %s", JidFile);
		}
	}
	if (securelevel > 0) {
		if (sysctlbyname("kern.securelevel", NULL, 0, &securelevel,
		    sizeof(securelevel)))
			err(1, "Can not set securelevel to %d", securelevel);
	}
	if (username != NULL) {
		if (Uflag)
			GET_USER_INFO;
		if (lflag) {
			p = getenv("TERM");
			environ = &cleanenv;
		}
		if (setgroups(ngroups, groups) != 0)
			err(1, "setgroups");
		if (setgid(pwd->pw_gid) != 0)
			err(1, "setgid");
		if (setusercontext(lcap, pwd, pwd->pw_uid,
		    LOGIN_SETALL & ~LOGIN_SETGROUP & ~LOGIN_SETLOGIN) != 0)
			err(1, "setusercontext");
		login_close(lcap);
	}
	if (lflag) {
		if (*pwd->pw_shell)
			shell = pwd->pw_shell;
		else
			shell = _PATH_BSHELL;
		if (chdir(pwd->pw_dir) < 0)
			errx(1, "no home directory");
		setenv("HOME", pwd->pw_dir, 1);
		setenv("SHELL", shell, 1);
		setenv("USER", pwd->pw_name, 1);
		if (p)
			setenv("TERM", p, 1);
	}
	if (execv(argv[3], argv + 3) != 0)
		err(1, "execv: %s", argv[3]);
	exit(0);
}

static void
usage(void)
{

	(void)fprintf(stderr, "%s%s%s\n",
	     "usage: jail [-i] [-J jid_file] [-s securelevel] [-l -u ",
	     "username | -U username]",
	     " path hostname ip1[,ip2[...]] command ...");
	exit(1);
}
