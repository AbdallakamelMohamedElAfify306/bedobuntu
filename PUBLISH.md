# Publish to GitHub and archive on Zenodo

Replace the remaining placeholder first: `AbdallakamelMohamedElAfify306` (your GitHub username) in
README, CITATION.cff and PUBLISH.md.

## 1. Scrub again on your machine

```
rg -n "password|PRIVATE KEY|BEGIN OPENSSH|/Users/|@gmail|IMEI|keystore|\.img" .
```

Fix anything personal. Confirm no bang characters if you keep that convention:

```
python3 -c "import pathlib; assert not any(chr(33) in p.read_text(errors='ignore') for p in pathlib.Path('.').rglob('*') if p.is_file() and p.stat().st_size < 2000000)"
```

Optional: install gitleaks and scan.

## 2. Create the GitHub repo (public)

On GitHub: New repository, public, no README (this tree already has one).

## 3. Init, commit, tag, push

```
cd pixel7pro-ubuntu-dualboot
git init -b main
git add .
git status
git commit -m "Release 0.1.0: Cheetah Dual public source drop"
git tag -a v0.1.0 -m "Cheetah Dual 0.1.0"
git remote add origin https://github.com/AbdallakamelMohamedElAfify306/bedobuntu.git
git push -u origin main
git push origin v0.1.0
```

Sign commits/tags with your GPG/SSH signing key if you use one (`commit -S`, `tag -s`).

## 4. GitHub Release

GitHub - Releases - Draft a new release - choose tag `v0.1.0` - publish.
Attach nothing that is an `.img`, key, or dump.

## 5. Zenodo

1. Sign in at https://zenodo.org with GitHub.
2. Optional: create https://orcid.org and link it.
3. Zenodo - GitHub settings - enable the repository toggle.
4. Publishing the GitHub release creates a Zenodo record and DOI automatically.
5. Check creators/license on the Zenodo record; paste the DOI badge into README.

Zenodo records are durable. Do not put secrets in the first release.

## 6. Announce upstream (optional)

Open a polite issue or discussion on derekross/omarchy-mobile describing that you
published an Ubuntu + Phosh variant derived from their MIT-licensed work, with a
link to your repo and DOI. Do not claim to be an official Ubuntu port.
