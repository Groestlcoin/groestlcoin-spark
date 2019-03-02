import { h, div, link, nav, a, span, p } from '@cycle/dom'
import numbro from 'numbro'
import { formatAmt } from '../util'
import { alertBox } from './util'

const layout = ({ state: S, body }) =>
  div({ props: { className: `d-flex flex-column theme-${S.conf.theme}${S.loading?' loading':'' }` } }, [
    navbar(S)
  , S.loading ? div('#loader') : ''
  , S.alert ? div('.container', alertBox(S.alert, !!S.info)) : ''
  , div('.content.container', body)
  , S.info ? footer(S) : ''
  ])

const navbar = ({ unitf, cbalance, obalance, page }) =>
  nav(`.navbar.navbar-dark.bg-primary.mb-3`, div('.container', [
    a('.navbar-brand', { attrs: { href: '#/' } }, [
      page.pathname != '/' ? span('.icon.icon-left-open') : ''
    , 'Groestlcoin Spark'
    ])
  , cbalance != null && obalance != null ? span('.toggle-unit.navbar-brand.mr-0', unitf(cbalance + obalance)) : ''
  ]))

const footer = ({ info, grsusd, msatusd, rate, conf: { unit, theme, expert } }) =>
  div('.main-bg',
    h('footer.container.clearfix.text-muted.border-top.border-light', [
      p('.info.float-left', [
        span('.toggle-exp', `${expert?'🔧 ':''} v${process.env.VERSION}`)

      , ` · ${info.network}`
      , ` · `, a({ attrs: { href: '#/node' } }, `node: ${info.id.substr(0,10)}`)

      , grsusd ? (
          [ 'usd', 'grs' ].includes(unit) ? ` · 1 grs = $${ numbro(grsusd).format(grsFormatOpt) }`
        : useCents(unit, grsusd) ? ` · 1 ${unitName(unit)} = ${formatAmt(1/rate*100, msatusd, 4, false)}¢`
        : ` · 1 ${unitName(unit)} = $${formatAmt(1/rate, msatusd, 3, false)}`
        ) : ''
      ])

    , p('.toggle-theme.float-right.btn-link', theme)
    ])
  )

// display gro and groestls as cents if they're worth less than $0.01
, useCents = (unit, grsusd) => (unit == 'gro' && +grsusd < 1000000) || (unit == 'groestls' && +grsusd < 10000)
, unitName = unit => unit.replace(/s$/, '')
, grsFormatOpt = { mantissa: 2, trimMantissa: true, optionalMantissa: true }

module.exports = { layout }
