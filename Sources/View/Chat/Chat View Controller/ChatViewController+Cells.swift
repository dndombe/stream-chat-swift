//
//  ChatViewController+Cells.swift
//  GetStreamChat
//
//  Created by Alexey Bukhtin on 04/05/2019.
//  Copyright © 2019 Stream.io Inc. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxGesture

// MARK: - Cells

extension ChatViewController {
    
    func messageCell(at indexPath: IndexPath, message: Message) -> UITableViewCell {
        guard let presenter = channelPresenter else {
            return .unused
        }
        
        let isIncoming = !message.user.isCurrent
        let cell = tableView.dequeueMessageCell(for: indexPath, style: isIncoming ? style.incomingMessage : style.outgoingMessage)
        
        if message.isDeleted {
            cell.update(info: "This message was deleted.", date: message.deleted)
        } else if message.isEphemeral {
            cell.update(message: message.args ?? "")
        } else {
            cell.update(message: message.textOrArgs)
            
            if !message.mentionedUsers.isEmpty {
                cell.update(mentionedUsersNames: message.mentionedUsers.map({ $0.name }))
            }
            
            if presenter.parentMessage == nil, presenter.channel.config.repliesEnabled, message.replyCount > 0 {
                cell.update(replyCount: message.replyCount)
                
                cell.replyCountButton.rx.anyGesture(TapControlEvent.default)
                    .subscribe(onNext: { [weak self] _ in self?.showReplies(parentMessage: message) })
                    .disposed(by: cell.disposeBag)
            }
        }
        
        var showAvatar = true
        let nextRow = indexPath.row + 1
        
        if nextRow < items.count, case .message(let nextMessage) = items[nextRow] {
            showAvatar = nextMessage.user != message.user
            
            if !showAvatar {
                cell.paddingType = .small
            }
        }
        
        var isContinueMessage = false
        let prevRow = indexPath.row - 1
        
        if prevRow >= 0,
            prevRow < items.count,
            case .message(let prevMessage) = items[prevRow],
            prevMessage.user == message.user,
            !prevMessage.text.messageContainsOnlyEmoji {
            isContinueMessage = true
        }
        
        cell.updateBackground(isContinueMessage: isContinueMessage)
        
        if showAvatar {
            cell.update(name: message.user.name, date: message.created)
            
            cell.avatarView.update(with: message.user.avatarURL,
                                   name: message.user.name,
                                   baseColor: style.incomingMessage.chatBackgroundColor)
        }
        
        guard !message.isDeleted else {
            return cell
        }
        
        if !message.attachments.isEmpty {
            cell.addAttachments(from: message,
                                tap: { [weak self] in self?.show(attachment: $0, at: $1, from: $2) },
                                actionTap: { [weak self] in self?.sendActionForEphemeral(message: $0, button: $1) },
                                reload: { [weak self] in
                                    if let self = self {
                                        self.tableView.reloadRows(at: [indexPath], with: .none)
                                    }
            })
            
            cell.updateBackground(isContinueMessage: !message.isEphemeral)
        }
        
        if !message.isEphemeral, presenter.channel.config.reactionsEnabled {
            update(cell: cell, forReactionsIn: message)
        }
        
        return cell
    }
    
    func willDisplay(cell: UITableViewCell, at indexPath: IndexPath, message: Message) {
        guard let cell = cell as? MessageTableViewCell,
            !message.isEphemeral,
            !message.isDeleted,
            let presenter = channelPresenter else {
            return
        }
        
        cell.messageStackView.rx.anyGesture(presenter.channel.config.reactionsEnabled
            ? [TapControlEvent.default, LongPressControlEvent.default]
            : [LongPressControlEvent.default])
            .subscribe(onNext: { [weak self, weak cell] gesture in
                if let self = self, let cell = cell {
                    let location = gesture.location(in: cell)
                    
                    if gesture is UITapGestureRecognizer {
                        self.showReactions(from: cell, in: message, locationInView: location)
                    } else {
                        self.showMenu(from: cell, for: message, locationInView: location)
                    }
                }
            })
            .disposed(by: cell.disposeBag)
    }
    
    private func show(attachment: Attachment, at index: Int, from attachments: [Attachment]) {
        if attachment.isImageOrVideo {
            showMediaGallery(with: attachments.compactMap {
                let logoImage = $0.type == .giphy ? UIImage.Logo.giphy : nil
                return MediaGalleryItem(title: $0.title, url: $0.imageURL, logoImage: logoImage)
                }, selectedIndex: index)
            
            return
        }
        
        showWebView(url: attachment.url, title: attachment.title)
    }
    
    private func userActivityCell(at indexPath: IndexPath, user: User, _ text: String) -> UITableViewCell {
        let cell = tableView.dequeueMessageCell(for: indexPath, style: style.incomingMessage)
        cell.update(info: text)
        cell.update(date: Date())
        cell.avatarView.update(with: user.avatarURL, name: user.name, baseColor: style.incomingMessage.chatBackgroundColor)
        return cell
    }
    
    func showReplies(parentMessage: Message) {
        guard let presenter = channelPresenter else {
            return
        }
        
        let messagePresenter = ChannelPresenter(channel: presenter.channel,
                                                parentMessage: parentMessage,
                                                showStatuses: presenter.showStatuses)
        
        let chatViewController = ChatViewController(nibName: nil, bundle: nil)
        chatViewController.channelPresenter = messagePresenter
        navigationController?.pushViewController(chatViewController, animated: true)
    }
}